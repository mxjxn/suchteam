defmodule SuchteamWeb.Plugs.DynamicContext do
  @moduledoc """
  A plug for dynamically injecting user-specific and environment-specific
  context into requests, enabling task personalization.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user_role = fetch_user_role(conn) || "viewer"
    deployment_env = Application.get_env(:suchteam, :environment, "test")

    context = %{
      user_role: user_role,
      deployment_env: deployment_env
    }

    assign(conn, :dynamic_context, context)
  end

  defp fetch_user_role(conn) do
    if session_fetched?(conn) do
      get_session(conn, :user_role) || conn.assigns[:user_role]
    else
      conn.assigns[:user_role]
    end
  end

  defp session_fetched?(conn) do
    Map.has_key?(conn.private, :plug_session)
  end
end
