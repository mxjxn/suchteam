# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Suchteam.Repo.insert!(%Suchteam.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Suchteam.{Repo, Accounts, Organizations, Agents}

# ⚠️  WARNING: This creates a demo account with a public password.
# This is for DEVELOPMENT and TESTING only!
# DO NOT run this in production, or change the password immediately after.

# Create demo user
IO.puts("Creating demo user...")
{:ok, user} = Accounts.register_user(%{
  email: "demo@suchteam.dev",
  password: "demo_password_123"  # ⚠️  DEMO PASSWORD - NOT FOR PRODUCTION!
})

IO.puts("✓ Demo user created: demo@suchteam.dev")

# Create demo organization
IO.puts("Creating demo organization...")
{:ok, org} = Organizations.create_organization(user, %{
  name: "Demo Organization",
  slug: "demo-org"
})

IO.puts("✓ Demo organization created: #{org.name}")

# Create a demo team
IO.puts("Creating demo team...")
{:ok, team} = Agents.create_team(%{
  name: "Demo Team",
  slug: "demo-team",
  organization_id: org.id,
  settings: %{
    "description" => "A demo team for testing"
  }
})

IO.puts("✓ Demo team created: #{team.name}")

# Create an API key
IO.puts("Creating demo API key...")
{:ok, api_key, plain_key} = Organizations.create_api_key(org.id, "Demo API Key")

IO.puts("✓ Demo API key created")
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("DEMO CREDENTIALS")
IO.puts(String.duplicate("=", 60))
IO.puts("\nWeb Login:")
IO.puts("  Email: demo@suchteam.dev")
IO.puts("  Password: demo_password_123")
IO.puts("\nAPI Key:")
IO.puts("  #{plain_key}")
IO.puts("\n⚠️  SAVE THIS API KEY - IT WON'T BE SHOWN AGAIN!")
IO.puts(String.duplicate("=", 60) <> "\n")

