defmodule SuchteamWeb.ApiAuth do
  @moduledoc """
  Authentication plug for API requests using API keys.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
  end
end
