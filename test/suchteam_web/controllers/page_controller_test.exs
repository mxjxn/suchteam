defmodule SuchteamWeb.PageControllerTest do
  use SuchteamWeb.ConnCase

  test "GET /login shows login page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Sign in"
  end

  test "GET / redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end
end
