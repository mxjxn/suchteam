defmodule SuchteamWeb.Api.HealthController do
  use SuchteamWeb, :controller

  alias Suchteam.OpenClaw.Client
  alias Suchteam.OpenClaw.HTTP

  def index(conn, _params) do
    openclaw_status = check_openclaw()

    status = if openclaw_status == :healthy, do: "healthy", else: "degraded"

    json(conn, %{
      status: status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      services: %{
        api: "ok",
        openclaw: if(openclaw_status == :healthy, do: "connected", else: "disconnected"),
        websocket: if(Client.connected?(), do: "connected", else: "disconnected")
      }
    })
  end

  defp check_openclaw do
    case HTTP.health_check() do
      {:ok, :healthy} -> :healthy
      _ -> :unhealthy
    end
  rescue
    _ -> :unhealthy
  end
end
