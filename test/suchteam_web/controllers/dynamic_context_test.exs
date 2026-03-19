defmodule SuchteamWeb.DynamicContextTest do
  use SuchteamWeb.ConnCase

  alias SuchteamWeb.Plugs.DynamicContext

  describe "DynamicContext Plug" do
    test "injects user and deployment context", %{conn: conn} do
      # Set up connection
      conn =
        conn
        |> Plug.Conn.assign(:user_role, "admin")
        |> Plug.Conn.assign(:deployment_env, "production")

      # Call DynamicContext plug
      conn = DynamicContext.call(conn, %{})

      # Assertions
      assert conn.assigns[:user_role] == "admin"
      assert conn.assigns[:deployment_env] == "production"
    end
  end
end
