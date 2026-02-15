defmodule Suchteam.OpenClaw.Client do
  use GenServer
  require Logger

  @default_timeout 30_000
  @reconnect_delay 5_000

  defstruct [:url, :token, :http_url, :pending_requests, :connected]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def connected? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, :is_connected)
    end
  catch
    :exit, _ -> false
  end

  def request(method, params \\ %{}, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:request, method, params}, timeout)
  catch
    :exit, _ -> {:error, :not_connected}
  end

  def send_agent_message(text, session_key \\ "main", timeout \\ @default_timeout) do
    params = %{text: text, sessionKey: session_key, options: %{stream: false}}
    request("agent", params, timeout)
  end

  def get_health(timeout \\ @default_timeout), do: request("health", %{}, timeout)
  def get_status(timeout \\ @default_timeout), do: request("status", %{}, timeout)

  @impl true
  def init(opts) do
    config = build_config(opts)

    state = %__MODULE__{
      url: config.gateway_url,
      token: config.token,
      http_url: config.http_url,
      pending_requests: %{},
      connected: false
    }

    schedule_connect()
    {:ok, state}
  end

  @impl true
  def handle_call(:is_connected, _from, state) do
    {:reply, state.connected, state}
  end

  def handle_call({:request, _method, _params}, _from, %{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:request, method, params}, from, state) do
    id = generate_id()
    pending = Map.put(state.pending_requests, id, from)
    message = %{type: "req", id: id, method: method, params: params}
    Suchteam.OpenClaw.WS.send(message)
    {:noreply, %{state | pending_requests: pending}}
  end

  @impl true
  def handle_info(:connect, %{connected: true} = state) do
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    Logger.info("[OpenClaw] Attempting to connect...")

    case Suchteam.OpenClaw.WS.start_link(url: state.url, token: state.token, client: self()) do
      {:ok, _pid} ->
        Logger.info("[OpenClaw] Connected")
        Phoenix.PubSub.broadcast(Suchteam.PubSub, "openclaw", :connected)
        {:noreply, %{state | connected: true}}

      {:error, reason} ->
        Logger.warning(
          "[OpenClaw] Connection failed: #{inspect(reason)}, retrying in #{@reconnect_delay}ms"
        )

        Phoenix.PubSub.broadcast(Suchteam.PubSub, "openclaw", {:disconnected, reason})
        schedule_connect()
        {:noreply, %{state | connected: false}}
    end
  end

  def handle_info(:ws_disconnected, state) do
    Logger.warning("[OpenClaw] Disconnected")
    Phoenix.PubSub.broadcast(Suchteam.PubSub, "openclaw", {:disconnected, :connection_lost})
    schedule_connect()
    {:noreply, %{state | connected: false}}
  end

  def handle_info({:ws_message, %{"id" => id, "type" => type, "payload" => payload}}, state) do
    case Map.get(state.pending_requests, id) do
      nil ->
        {:noreply, state}

      from ->
        result = if type == "res", do: {:ok, payload}, else: {:error, payload}
        GenServer.reply(from, result)
        {:noreply, %{state | pending_requests: Map.delete(state.pending_requests, id)}}
    end
  end

  def handle_info({:ws_message, %{"type" => "event", "payload" => payload}}, state) do
    Phoenix.PubSub.broadcast(Suchteam.PubSub, "openclaw", {:event, payload})
    {:noreply, state}
  end

  def handle_info({:ws_message, %{"type" => "auth_success"}}, state) do
    Logger.info("[OpenClaw] Authentication successful")
    {:noreply, state}
  end

  def handle_info({:ws_message, _}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_connect do
    Process.send_after(self(), :connect, @reconnect_delay)
  end

  defp build_config(opts) do
    default = Application.get_env(:suchteam, :open_claw, [])

    %{
      gateway_url: opts[:gateway_url] || default[:gateway_url] || "ws://localhost:18789",
      http_url: opts[:http_url] || default[:http_url] || "http://localhost:18789",
      token: opts[:token] || default[:token],
      reconnect_interval: opts[:reconnect_interval] || default[:reconnect_interval] || 5000
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

defmodule Suchteam.OpenClaw.WS do
  use WebSockex
  require Logger

  def start_link(opts) do
    url = opts[:url]
    token = opts[:token]
    client = opts[:client]

    ws_url = if token && token != "", do: "#{url}?token=#{token}", else: url

    WebSockex.start_link(ws_url, __MODULE__, %{client: client})
  end

  def send(message) do
    WebSockex.cast(__MODULE__, {:send, {:text, Jason.encode!(message)}})
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, message} -> send(state.client, {:ws_message, message})
      {:error, _} -> :ok
    end

    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: _reason}, state) do
    send(state.client, :ws_disconnected)
    {:ok, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("[OpenClaw WS] Terminated: #{inspect(reason)}")
    :ok
  end
end
