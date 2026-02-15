# Subscription & Billing Strategy

This document outlines the subscription model, pricing strategy, and billing implementation for Suchteam SaaS.

## Subscription Tiers

### Free Tier (Freemium)
**Price:** $0/month

**Limits:**
- 5 agents maximum
- 100 tasks per day
- 100 API calls per hour
- Basic web interface
- Community support

**Target Audience:**
- Individual developers
- Students
- Side projects
- Trial users

**Conversion Strategy:**
- Easy onboarding with no credit card required
- Clear visibility of usage limits
- In-app prompts when approaching limits
- Upgrade CTAs in dashboard

### Pro Tier
**Price:** $49/month (suggested)

**Limits:**
- 50 agents
- 10,000 tasks per day
- 1,000 API calls per hour

**Features:**
- Everything in Free
- Full API access
- Priority support (24-48hr response)
- Advanced analytics
- Team collaboration (up to 5 members)

**Target Audience:**
- Small teams (2-10 people)
- Startups
- Production applications
- Professional developers

**Value Proposition:**
- 10x capacity increase
- Professional support
- Reliable for production workloads

### Enterprise Tier
**Price:** Custom (starts at $499/month)

**Limits:**
- Unlimited agents
- Unlimited tasks
- Unlimited API calls

**Features:**
- Everything in Pro
- Dedicated support
- SLA (99.9% uptime guarantee)
- Custom integrations
- SSO (SAML/OAuth)
- On-premise deployment option
- Custom billing terms
- Technical account manager
- Training and onboarding

**Target Audience:**
- Large organizations (50+ employees)
- Enterprise companies
- High-volume users
- Organizations with compliance requirements

**Sales Model:**
- Contact sales for pricing
- Custom contracts
- Annual commitments with discount
- Volume-based pricing

## Usage-Based Pricing (Future)

### Pay-As-You-Go Model

In addition to subscription tiers, offer usage-based pricing:

**Agent Hours:**
- Free tier: Included in base
- Pro: Included in base
- Enterprise: $0.10 per agent-hour above threshold

**Task Execution:**
- $0.001 per task (10,000 tasks = $10)
- Volume discounts at scale

**API Calls:**
- $0.0001 per call (10,000 calls = $1)
- Bundled in subscriptions up to limits

**Example Pricing:**
```
Base subscription: $49/month (Pro)
+ 100 extra agent-hours: $10
+ 50,000 extra tasks: $50
+ 500,000 extra API calls: $50
= Total: $159/month
```

## Billing Implementation

### Stripe Integration

**1. Install Stripe library:**
```elixir
# mix.exs
{:stripe, "~> 3.0"}
```

**2. Configure Stripe:**
```elixir
# config/runtime.exs
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY"),
  public_key: System.get_env("STRIPE_PUBLIC_KEY")
```

**3. Create Stripe customers:**
```elixir
defmodule Suchteam.Billing.Stripe do
  alias Stripe.Customer
  
  def create_customer(organization, user) do
    Customer.create(%{
      email: user.email,
      name: organization.name,
      metadata: %{
        organization_id: organization.id
      }
    })
  end
end
```

**4. Create subscriptions:**
```elixir
def create_subscription(customer_id, price_id) do
  Stripe.Subscription.create(%{
    customer: customer_id,
    items: [%{price: price_id}],
    metadata: %{
      organization_id: organization_id
    }
  })
end
```

**5. Handle webhooks:**
```elixir
defmodule SuchteamWeb.StripeWebhookController do
  use SuchteamWeb, :controller
  
  def handle(conn, _params) do
    payload = conn.assigns.raw_body
    sig_header = get_req_header(conn, "stripe-signature")
    
    case Stripe.Webhook.construct_event(payload, sig_header, webhook_secret()) do
      {:ok, event} -> handle_event(event)
      {:error, _} -> conn |> put_status(400) |> json(%{error: "Invalid signature"})
    end
  end
  
  defp handle_event(%{type: "customer.subscription.updated", data: %{object: subscription}}) do
    # Update subscription in database
    Billing.update_subscription_from_stripe(subscription)
  end
  
  defp handle_event(%{type: "customer.subscription.deleted", data: %{object: subscription}}) do
    # Cancel subscription
    Billing.cancel_subscription_from_stripe(subscription)
  end
  
  defp handle_event(%{type: "invoice.payment_failed", data: %{object: invoice}}) do
    # Handle failed payment
    Billing.handle_payment_failure(invoice)
  end
end
```

### Pricing Plans in Stripe

**Create price objects:**
```bash
# Free (no Stripe subscription needed)

# Pro - Monthly
stripe prices create \
  --product=prod_pro \
  --currency=usd \
  --unit-amount=4900 \
  --recurring[interval]=month

# Pro - Annual (16% discount)
stripe prices create \
  --product=prod_pro \
  --currency=usd \
  --unit-amount=49416 \
  --recurring[interval]=year

# Enterprise (custom - handled manually)
```

### Subscription Lifecycle

**1. User upgrades:**
```
User clicks "Upgrade to Pro"
  → Redirect to Stripe Checkout
  → User enters payment details
  → Stripe creates subscription
  → Webhook updates database
  → User sees Pro features
```

**2. Monthly billing cycle:**
```
Day 1: Subscription created
Day 30: Stripe charges customer
  → If successful: Continue service
  → If failed: Send payment reminder
Day 32: Retry payment
Day 34: Retry payment
Day 37: Subscription past_due
  → Limit service (read-only mode)
Day 44: Cancel subscription
  → Downgrade to Free tier
```

**3. User cancels:**
```
User clicks "Cancel subscription"
  → Set cancel_at_period_end = true
  → Continue service until period ends
  → At period end: Downgrade to Free
```

### Proration Handling

**Upgrade mid-cycle:**
```elixir
# Stripe automatically prorates
Stripe.Subscription.update(subscription_id, %{
  items: [%{
    id: item_id,
    price: new_price_id
  }],
  proration_behavior: "always_invoice"  # or "create_prorations"
})
```

## Usage Tracking & Metering

### Track Usage for Billing

**1. Record metered usage:**
```elixir
def record_metered_usage(organization_id, metric_type, quantity) do
  # Record in local database for analytics
  Billing.record_usage(organization_id, metric_type, quantity)
  
  # Report to Stripe for metered billing
  if has_stripe_subscription?(organization_id) do
    report_to_stripe(organization_id, metric_type, quantity)
  end
end
```

**2. Report to Stripe:**
```elixir
defp report_to_stripe(organization_id, "api_calls", quantity) do
  subscription = get_subscription(organization_id)
  
  Stripe.SubscriptionItem.Usage.create(
    subscription.stripe_subscription_item_id,
    %{
      quantity: quantity,
      timestamp: DateTime.utc_now() |> DateTime.to_unix(),
      action: "increment"
    }
  )
end
```

### Billing Alerts

**Send alerts when approaching limits:**
```elixir
defmodule Suchteam.Billing.Alerts do
  def check_usage_alerts(organization_id) do
    subscription = Billing.get_subscription(organization_id)
    usage = Billing.get_current_usage(organization_id)
    limits = Subscription.plan_limits(subscription.plan)
    
    # Alert at 80% of limit
    if usage.api_calls > limits.max_api_calls_per_hour * 0.8 do
      send_usage_alert(organization_id, :api_calls, usage.api_calls, limits.max_api_calls_per_hour)
    end
  end
  
  defp send_usage_alert(organization_id, metric, current, limit) do
    # Send email via Swoosh
    # Show in-app notification
    # Log for admin review
  end
end
```

## Revenue Optimization

### Pricing Psychology

**1. Anchor pricing:**
- Show Enterprise price to make Pro look affordable
- "Most Popular" badge on Pro tier
- Annual discount (pay 10 months, get 12)

**2. Feature comparison table:**
```
                Free    Pro     Enterprise
Agents          5       50      Unlimited
Tasks/day       100     10K     Unlimited
API calls/hr    100     1K      Unlimited
Support         Community 24-48hr Dedicated
Price           $0      $49/mo  Custom
```

**3. Social proof:**
- "Trusted by 10,000+ developers"
- Customer testimonials
- Case studies from Pro/Enterprise users

### Conversion Optimization

**Free to Pro:**
- Trial period: 14-day Pro trial for Free users
- Usage prompts: "You're using 95% of your API calls"
- Feature gates: "This feature requires Pro"
- Success stories: Show what Pro users achieve

**Pro to Enterprise:**
- Dedicated sales outreach at usage thresholds
- Custom demo and onboarding
- ROI calculator showing cost savings
- White-glove migration support

### Retention Strategies

**1. Reduce churn:**
- Usage alerts before hitting limits
- Flexible downgrade options
- Pause subscription feature
- Win-back campaigns for cancelled users

**2. Expand revenue:**
- Usage-based upsells
- Add-on features (extra storage, etc.)
- Team seats (additional members)
- Premium support packages

**3. Annual commitments:**
- 2 months free for annual plans
- Priority feature requests
- Dedicated success manager
- Early access to new features

## Financial Projections

### Revenue Model

**Year 1 Goals:**
- 1,000 Free users (0 MRR)
- 50 Pro users ($2,450 MRR)
- 3 Enterprise users ($1,500+ MRR)
- **Total: ~$4,000 MRR**

**Year 2 Goals:**
- 5,000 Free users
- 250 Pro users ($12,250 MRR)
- 15 Enterprise users ($7,500+ MRR)
- **Total: ~$20,000 MRR**

**Growth Metrics:**
- Free-to-Pro conversion: 5%
- Pro-to-Enterprise: 6%
- Monthly churn: <5%
- Annual growth: 300%

### Cost Structure

**Fixed Costs:**
- Infrastructure: $500/month (scales with usage)
- Stripe fees: 2.9% + $0.30 per transaction
- Support tools: $200/month
- Email service: $50/month

**Variable Costs:**
- Database: ~$0.10 per GB
- Bandwidth: ~$0.09 per GB
- Oban workers: Scales with usage

**Unit Economics:**
- Pro customer acquisition cost: $150
- Lifetime value (2 year average): $1,176
- LTV:CAC ratio: 7.8:1 ✅

## Implementation Checklist

### Phase 1: Basic Billing (MVP)
- [ ] Stripe account setup
- [ ] Product and price creation in Stripe
- [ ] Checkout integration
- [ ] Webhook handling
- [ ] Subscription status sync
- [ ] Basic upgrade/downgrade flows

### Phase 2: Enhanced Features
- [ ] Usage-based pricing
- [ ] Prorated billing
- [ ] Annual plans
- [ ] Team seats
- [ ] Invoice generation
- [ ] Payment method management

### Phase 3: Enterprise Features
- [ ] Custom contracts
- [ ] Quote generation
- [ ] Manual invoicing
- [ ] Purchase orders
- [ ] Multi-year commitments
- [ ] Volume discounts

### Phase 4: Optimization
- [ ] A/B test pricing
- [ ] Churn analysis
- [ ] Cohort reporting
- [ ] Revenue forecasting
- [ ] Customer segmentation
- [ ] Win-back campaigns

## Legal & Compliance

### Required Documents

**1. Terms of Service:**
- Service description
- Payment terms
- Refund policy
- Usage limits
- Termination conditions
- Liability limitations

**2. Privacy Policy:**
- Data collection practices
- Data storage and security
- Third-party services (Stripe)
- User rights (GDPR, CCPA)
- Cookie policy

**3. SLA (Enterprise):**
- Uptime guarantees (99.9%)
- Response times
- Compensation for downtime
- Maintenance windows

### Tax Compliance

**Sales Tax:**
- Use Stripe Tax for automatic calculation
- Register in states with nexus
- File quarterly reports

**International:**
- VAT for EU customers
- GST for Australia, Singapore
- Use Stripe Billing for automatic handling

## Support

For billing questions:
- Check [SaaS Guide](./SAAS_GUIDE.md)
- Review [Deployment Guide](./DEPLOYMENT.md)
- Contact billing@suchteam.dev
- Open support ticket in dashboard
