defmodule Suchteam.OpenClaw.HTTP do
  use GenServer
  require Logger

  @pool_name :openclaw_http_pool

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def invoke_tool(tool, args \\ %{}, session_key \\ "main") do
    config = get_config()
    url = "#{config.http_url}/tools/invoke"

    body =
      Jason.encode!(%{
        tool: tool,
        args: args,
        sessionKey: session_key
      })

    headers = build_headers(config.token)

    case Finch.build(:post, url, headers, body) |> Finch.request(@pool_name) do
      {:ok, %Finch.Response{status: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"result" => result}} -> {:ok, result}
          {:ok, %{"error" => error}} -> {:error, error}
          {:error, _} = err -> err
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, _} = error ->
        error
    end
  end

  def health_check do
    config = get_config()
    url = "#{config.http_url}/health"
    headers = build_headers(config.token)

    case Finch.build(:get, url, headers) |> Finch.request(@pool_name) do
      {:ok, %Finch.Response{status: 200}} -> {:ok, :healthy}
      {:ok, %Finch.Response{status: status}} -> {:error, {:unhealthy, status}}
      {:error, _} = error -> error
    end
  end

  def get_config do
    config = Application.get_env(:suchteam, :open_claw, [])

    %{
      http_url: config[:http_url] || "http://localhost:18789",
      token: config[:token]
    }
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:suchteam, :open_claw, [])
    http_url = opts[:http_url] || config[:http_url] || "http://localhost:18789"

    {:ok, _} = Finch.start_link(name: @pool_name)

    {:ok, %{http_url: http_url, token: opts[:token] || config[:token]}}
  end

  defp build_headers(token) do
    base = [{"content-type", "application/json"}]
    if token, do: [{"authorization", "Bearer #{token}"} | base], else: base
  end
end
