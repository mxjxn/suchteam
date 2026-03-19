ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Suchteam.Repo, :manual)

# Ensure Suchteam.Repo is loaded and started for tests
Application.ensure_all_started(:suchteam)
