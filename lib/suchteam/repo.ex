defmodule Suchteam.Repo do
  use Ecto.Repo,
    otp_app: :suchteam,
    adapter: Ecto.Adapters.Postgres
end
