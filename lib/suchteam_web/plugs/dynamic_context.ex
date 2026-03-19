defmodule SuchteamWeb.Plugs.DynamicContext do
  @moduledoc """
  A plug for dynamically injecting user-specific and environment-specific
  context into requests, enabling task personalization.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Fetch user role and environment dynamically (adjust to fit your data sources)
    user_role = fetch_user_role(conn) || "viewer"
    deployment_env = Application.get_env(:suchteam, :environment, "test")

    # Construct dynamic context
    context = %{
      user_role: user_role,
      deployment_env: deployment_env
    }

    # Assign context to the connection for downstream usage
    assign(conn, :dynamic_context, context)
  end

  defp fetch_user_role(conn) do
    # You can fetch the user role from the session, headers, or database
    get_session(conn, :user_role) || conn.assigns[:user_role]
  end
end
