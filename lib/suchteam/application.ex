defmodule Suchteam.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SuchteamWeb.Telemetry,
      Suchteam.Repo,
      {DNSCluster, query: Application.get_env(:suchteam, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Suchteam.PubSub},
      {Finch, name: Suchteam.Finch},
      Suchteam.OpenClaw.Supervisor,
      Suchteam.Orchestrator,
      SuchteamWeb.Endpoint
    ]

    children =
      if Mix.env() != :test do
        children ++ [{Oban, Application.get_env(:suchteam, Oban, repo: Suchteam.Repo)}]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Suchteam.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SuchteamWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
