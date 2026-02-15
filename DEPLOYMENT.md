# Deployment Guide - Suchteam SaaS

This guide covers deploying Suchteam as a production SaaS application.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Platform Options](#platform-options)
3. [Environment Setup](#environment-setup)
4. [Database Setup](#database-setup)
5. [Security Configuration](#security-configuration)
6. [Deployment Steps](#deployment-steps)
7. [Post-Deployment](#post-deployment)
8. [Monitoring](#monitoring)
9. [Scaling](#scaling)

## Prerequisites

Before deploying, ensure you have:

- ✅ Elixir 1.14+ installed
- ✅ PostgreSQL 16+ database
- ✅ Domain name configured
- ✅ SSL certificate (Let's Encrypt recommended)
- ✅ SMTP service for emails (optional but recommended)
- ✅ Stripe account (if accepting payments)

## Platform Options

### Option 1: Fly.io (Recommended)

Fly.io is ideal for Phoenix/Elixir applications with global edge deployment.

**Pros:**
- Native Elixir support
- Built-in PostgreSQL
- Global edge network
- Easy scaling
- Free tier available

**Quick Deploy:**
```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Login
fly auth login

# Launch (creates fly.toml)
fly launch

# Add secrets
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set DATABASE_URL=<your_postgres_url>

# Deploy
fly deploy
```

### Option 2: Render

**Pros:**
- Simple deployment
- Managed PostgreSQL
- Automatic SSL
- Easy rollbacks

**Deploy via render.yaml:**
```yaml
services:
  - type: web
    name: suchteam
    env: elixir
    buildCommand: mix deps.get --only prod && mix assets.deploy && mix phx.digest
    startCommand: mix phx.server
    envVars:
      - key: DATABASE_URL
        fromDatabase:
          name: suchteam-db
          property: connectionString
      - key: SECRET_KEY_BASE
        generateValue: true
      - key: PHX_HOST
        value: suchteam.onrender.com
      - key: PORT
        value: 4000

databases:
  - name: suchteam-db
    databaseName: suchteam
    user: suchteam
```

### Option 3: Gigalixir

Phoenix-focused platform with built-in support for hot upgrades.

```bash
# Install CLI
pip3 install gigalixir

# Login
gigalixir login

# Create app
gigalixir create -n suchteam

# Add database
gigalixir pg:create --free

# Deploy
git push gigalixir main
```

### Option 4: Self-Hosted (VPS/EC2)

For full control, deploy on your own infrastructure.

See [Self-Hosted Deployment](#self-hosted-deployment) section below.

## Environment Setup

### Required Environment Variables

```bash
# Generate secret key base
SECRET_KEY_BASE=$(mix phx.gen.secret)

# Database
DATABASE_URL=postgresql://user:pass@host:5432/suchteam_prod

# Phoenix
PHX_HOST=suchteam.yourdomain.com
PORT=4000

# SSL (production)
FORCE_SSL=true
```

### Optional Environment Variables

```bash
# Redis (for caching)
REDIS_URL=redis://localhost:6379

# OpenClaw (if using)
OPENCLAW_ENABLED=true
OPENCLAW_GATEWAY_URL=wss://openclaw.yourdomain.com
OPENCLAW_HTTP_URL=https://openclaw.yourdomain.com
OPENCLAW_GATEWAY_TOKEN=<secure_token>

# Email
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=<your_sendgrid_key>
FROM_EMAIL=noreply@yourdomain.com

# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_PUBLIC_KEY=pk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

# SaaS Settings
SAAS_MODE=true
ALLOW_REGISTRATION=true
REQUIRE_EMAIL_VERIFICATION=false
```

## Database Setup

### 1. Create Production Database

```bash
createdb suchteam_prod
```

### 2. Run Migrations

```bash
MIX_ENV=prod mix ecto.migrate
```

### 3. Seed Initial Data (Optional)

```bash
MIX_ENV=prod mix run priv/repo/seeds.exs
```

### 4. Database Backups

Set up automated backups:

**PostgreSQL with pg_dump:**
```bash
#!/bin/bash
# backup.sh
DATE=$(date +%Y%m%d_%H%M%S)
pg_dump $DATABASE_URL > backups/suchteam_$DATE.sql
gzip backups/suchteam_$DATE.sql

# Keep last 30 days
find backups/ -name "*.sql.gz" -mtime +30 -delete
```

**Run daily via cron:**
```cron
0 2 * * * /path/to/backup.sh
```

## Security Configuration

### 1. Generate Strong Secret Key

```bash
mix phx.gen.secret
```

Use this for `SECRET_KEY_BASE` environment variable.

### 2. Enable Force SSL

In `config/prod.exs`:
```elixir
config :suchteam, SuchteamWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  url: [host: System.get_env("PHX_HOST"), port: 443, scheme: "https"]
```

### 3. Configure CSP Headers

Add Content Security Policy headers in `endpoint.ex`:
```elixir
plug Plug.Static,
  at: "/",
  from: :suchteam,
  gzip: false,
  only: ~w(assets fonts images favicon.ico robots.txt),
  headers: %{
    "content-security-policy" => "default-src 'self'"
  }
```

### 4. Rate Limiting (Optional)

Install `hammer` for rate limiting:
```elixir
{:hammer, "~> 6.0"}
```

## Deployment Steps

### Fly.io Deployment

1. **Create fly.toml:**
```toml
app = "suchteam"
primary_region = "sjc"

[build]

[env]
  PHX_HOST = "suchteam.fly.dev"
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
  min_machines_running = 0

[[services]]
  protocol = "tcp"
  internal_port = 8080

  [[services.ports]]
    port = 80
    handlers = ["http"]

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

[[services.http_checks]]
  interval = "10s"
  timeout = "2s"
  grace_period = "5s"
  method = "GET"
  path = "/api/health"

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1
```

2. **Create PostgreSQL:**
```bash
fly postgres create --name suchteam-db
fly postgres attach suchteam-db
```

3. **Set secrets:**
```bash
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
```

4. **Deploy:**
```bash
fly deploy
```

5. **Run migrations:**
```bash
fly ssh console -C "app/bin/migrate"
```

### Render Deployment

1. **Connect GitHub repo** to Render
2. **Create PostgreSQL database** in Render dashboard
3. **Create Web Service** with:
   - Build Command: `mix deps.get --only prod && MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix phx.digest`
   - Start Command: `MIX_ENV=prod mix phx.server`
4. **Add environment variables** from Render dashboard
5. **Deploy** automatically on git push

### Self-Hosted Deployment

#### Prerequisites
- Ubuntu 20.04+ or similar
- Nginx for reverse proxy
- Systemd for process management

#### 1. Install Dependencies

```bash
# Install Erlang and Elixir
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install esl-erlang elixir

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PostgreSQL
sudo apt-get install postgresql postgresql-contrib
```

#### 2. Build Release

```bash
# On your local machine or CI
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix phx.digest
MIX_ENV=prod mix release

# Creates _build/prod/rel/suchteam/
```

#### 3. Deploy Release

```bash
# Copy to server
scp -r _build/prod/rel/suchteam user@server:/opt/suchteam

# On server
sudo chown -R suchteam:suchteam /opt/suchteam
```

#### 4. Create Systemd Service

`/etc/systemd/system/suchteam.service`:
```ini
[Unit]
Description=Suchteam Phoenix App
After=network.target postgresql.service

[Service]
Type=simple
User=suchteam
Group=suchteam
WorkingDirectory=/opt/suchteam
Environment="PORT=4000"
Environment="PHX_HOST=suchteam.yourdomain.com"
Environment="SECRET_KEY_BASE=<your_secret>"
Environment="DATABASE_URL=<your_db_url>"
ExecStart=/opt/suchteam/bin/suchteam start
ExecStop=/opt/suchteam/bin/suchteam stop
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=suchteam

[Install]
WantedBy=multi-user.target
```

#### 5. Configure Nginx

`/etc/nginx/sites-available/suchteam`:
```nginx
upstream phoenix {
  server 127.0.0.1:4000;
}

server {
  listen 80;
  server_name suchteam.yourdomain.com;
  
  # Redirect to HTTPS
  return 301 https://$server_name$request_uri;
}

server {
  listen 443 ssl http2;
  server_name suchteam.yourdomain.com;

  ssl_certificate /etc/letsencrypt/live/suchteam.yourdomain.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/suchteam.yourdomain.com/privkey.pem;

  location / {
    proxy_pass http://phoenix;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```

#### 6. Start Service

```bash
sudo systemctl enable suchteam
sudo systemctl start suchteam
sudo systemctl status suchteam

# Enable and start Nginx
sudo ln -s /etc/nginx/sites-available/suchteam /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Post-Deployment

### 1. Verify Deployment

```bash
# Check health endpoint
curl https://suchteam.yourdomain.com/api/health

# Should return:
# {"status":"ok","timestamp":"2024-02-15T12:00:00Z"}
```

### 2. Create Admin User

```bash
# Via IEx on production
iex -S mix # or fly ssh console for Fly.io

# In IEx:
alias Suchteam.{Accounts, Organizations}

{:ok, admin} = Accounts.register_user(%{
  email: "admin@yourdomain.com",
  password: "secure_admin_password_123"
})

{:ok, org} = Organizations.create_organization(admin, %{
  name: "Admin Organization"
})

{:ok, _key, plain_key} = Organizations.create_api_key(org.id, "Admin API Key")
IO.puts("Admin API Key: #{plain_key}")
```

### 3. Configure DNS

Point your domain to your deployment:
- **Fly.io**: `suchteam.fly.dev` (get IP with `fly ips list`)
- **Render**: Provided by Render
- **Self-hosted**: Your server's IP

### 4. Set Up SSL

**Fly.io/Render**: Automatic

**Self-hosted**:
```bash
sudo certbot --nginx -d suchteam.yourdomain.com
```

### 5. Test User Flow

1. Visit https://suchteam.yourdomain.com
2. Register a new account
3. Create an organization
4. Generate API key
5. Test API endpoints

## Monitoring

### Application Monitoring

**1. Enable Phoenix LiveDashboard (production with auth):**

```elixir
# In router.ex
import Phoenix.LiveDashboard.Router

scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin]
  
  live_dashboard "/dashboard",
    metrics: SuchteamWeb.Telemetry,
    additional_pages: [
      oban: {Oban.Plugins.LiveDashboard, []}
    ]
end
```

**2. Add error tracking:**

```elixir
# Sentry
{:sentry, "~> 8.0"}

# In config/prod.exs
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: :prod,
  enable_source_code_context: true,
  root_source_code_path: File.cwd!()
```

**3. Add APM (Application Performance Monitoring):**

```elixir
# AppSignal
{:appsignal_phoenix, "~> 2.0"}
```

### Infrastructure Monitoring

- **Uptime monitoring**: UptimeRobot, Pingdom
- **Log aggregation**: Papertrail, Logtail
- **Metrics**: Prometheus + Grafana

## Scaling

### Vertical Scaling (Single Instance)

Increase resources on your platform:
```bash
# Fly.io
fly scale memory 2048  # 2GB RAM
fly scale cpu 2        # 2 CPUs

# Render
# Upgrade via dashboard
```

### Horizontal Scaling (Multiple Instances)

Phoenix applications scale horizontally with minimal changes:

**1. Enable distributed Erlang:**
```elixir
# In config/prod.exs
config :suchteam, Suchteam.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

config :libcluster,
  topologies: [
    fly: [
      strategy: Cluster.Strategy.DNSPoll,
      config: [
        polling_interval: 5_000,
        query: System.get_env("FLY_APP_NAME") <> ".internal",
        node_basename: System.get_env("FLY_APP_NAME")
      ]
    ]
  ]
```

**2. Scale instances:**
```bash
# Fly.io
fly scale count 3  # Run 3 instances

# Render
# Add autoscaling rules in dashboard
```

### Database Scaling

**Read replicas:**
```elixir
# Add read replica
config :suchteam, Suchteam.ReadRepo,
  url: System.get_env("READ_REPLICA_URL"),
  pool_size: 10
```

**Connection pooling:**
```bash
# Use PgBouncer
# Fly.io has this built-in
```

## Troubleshooting

### Common Issues

**1. Database connection errors:**
```bash
# Check DATABASE_URL is set correctly
echo $DATABASE_URL

# Test connection
psql $DATABASE_URL -c "SELECT 1"
```

**2. Migration failures:**
```bash
# Reset and re-run
mix ecto.reset
mix ecto.migrate
```

**3. Asset compilation errors:**
```bash
# Clean and rebuild
rm -rf _build deps assets/node_modules
mix deps.get
mix assets.deploy
```

**4. Memory issues:**
```bash
# Increase heap size
export ERL_MAX_PORTS=16384
export BEAM_OPTS="+hms 1024"
```

### Logs

**Fly.io:**
```bash
fly logs
```

**Render:**
Check logs in dashboard

**Self-hosted:**
```bash
journalctl -u suchteam -f
```

## Checklist

Before going live:

- [ ] SECRET_KEY_BASE is secure and unique
- [ ] Database backups are configured
- [ ] SSL/HTTPS is enforced
- [ ] Email delivery is tested
- [ ] Monitoring is set up
- [ ] DNS is configured
- [ ] Error tracking is enabled
- [ ] Terms of Service and Privacy Policy are added
- [ ] Subscription plans are configured
- [ ] Stripe webhooks are tested (if using payments)
- [ ] Rate limiting is verified
- [ ] API documentation is published

## Support

For deployment issues:
- Check the [SaaS Guide](./SAAS_GUIDE.md)
- Review [API Documentation](./API.md)
- Open an issue on GitHub
- Contact support@suchteam.dev
