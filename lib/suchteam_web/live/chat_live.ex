defmodule SuchteamWeb.ChatLive do
  use SuchteamWeb, :live_view

  alias Suchteam.Agents
  alias Suchteam.Orchestrator

  @chat_history_limit 100

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "agents")
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "chat")

    agents = load_available_agents()

    {:ok,
     socket
     |> assign(
       messages: [],
       input_message: "",
       agents: agents,
       selected_agent: nil,
       files: get_file_tree(),
       expanded_dirs: MapSet.new()
     )}
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"text" => text}}, socket) when text != "" do
    message = %{
      id: generate_id(),
      text: text,
      role: "user",
      timestamp: DateTime.utc_now()
    }

    new_messages = socket.assigns.messages ++ [message]

    if socket.assigns.selected_agent do
      delegate_to_agent(socket.assigns.selected_agent, text)
    end

    {:noreply, assign(socket, messages: new_messages, input_message: "")}
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_input", %{"message" => %{"text" => text}}, socket) do
    {:noreply, assign(socket, :input_message, text)}
  end

  def handle_event("select_agent", %{"id" => agent_id}, socket) do
    agent = Agents.get_agent(agent_id)
    {:noreply, assign(socket, selected_agent: agent)}
  end

  def handle_event("toggle_dir", %{"path" => path}, socket) do
    expanded = socket.assigns.expanded_dirs

    expanded =
      if MapSet.member?(expanded, path) do
        MapSet.delete(expanded, path)
      else
        MapSet.put(expanded, path)
      end

    {:noreply, assign(socket, :expanded_dirs, expanded)}
  end

  def handle_event("refresh_files", _params, socket) do
    {:noreply, assign(socket, :files, get_file_tree())}
  end

  @impl true
  def handle_info({:task_completed, %{result: result}}, socket) do
    message = %{
      id: generate_id(),
      text: format_result(result),
      role: "assistant",
      timestamp: DateTime.utc_now()
    }

    new_messages = (socket.assigns.messages ++ [message]) |> Enum.take(-@chat_history_limit)
    {:noreply, assign(socket, :messages, new_messages)}
  end

  def handle_info({:created, _agent}, socket) do
    {:noreply, assign(socket, :agents, load_available_agents())}
  end

  def handle_info({:terminated, _agent}, socket) do
    {:noreply, assign(socket, :agents, load_available_agents())}
  end

  def handle_info({:status_changed, _agent}, socket) do
    {:noreply, assign(socket, :agents, load_available_agents())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-gray-900 text-white">
      <div class="flex items-center justify-between px-6 py-4 border-b border-gray-700">
        <h1 class="text-xl font-bold">Chat Interface</h1>
        <.link navigate={~p"/"} class="text-sm text-gray-400 hover:text-white">
          Back to Dashboard
        </.link>
      </div>

      <div class="flex-1 flex overflow-hidden">
        <div class="flex-1 flex flex-col">
          <div class="flex-1 overflow-y-auto p-6 space-y-4" id="chat-messages">
            <div
              :for={msg <- @messages}
              class={"flex #{msg.role == "user" && "justify-end" || "justify-start"}"}
            >
              <div class={"max-w-2xl rounded-lg px-4 py-3 #{msg.role == "user" && "bg-blue-600" || "bg-gray-700"}"}>
                <p class="whitespace-pre-wrap">{msg.text}</p>
                <p class="text-xs text-gray-300 mt-2">{format_time(msg.timestamp)}</p>
              </div>
            </div>

            <div :if={Enum.empty?(@messages)} class="text-center text-gray-400 py-20">
              <p class="text-lg mb-2">No messages yet</p>
              <p class="text-sm">Select an agent from the right panel and start chatting</p>
            </div>
          </div>

          <div class="border-t border-gray-700 p-4">
            <form phx-submit="send_message" class="flex gap-4">
              <input
                type="text"
                name="message[text]"
                value={@input_message}
                phx-input="update_input"
                placeholder={
                  if @selected_agent,
                    do: "Message #{@selected_agent.type} agent...",
                    else: "Select an agent first..."
                }
                class="flex-1 bg-gray-800 rounded-lg px-4 py-3 border border-gray-600 focus:border-blue-500 focus:outline-none"
              />
              <button
                type="submit"
                disabled={is_nil(@selected_agent)}
                class="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed px-6 py-3 rounded-lg font-medium"
              >
                Send
              </button>
            </form>
          </div>
        </div>

        <div class="w-80 border-l border-gray-700 flex flex-col">
          <div class="flex-1 overflow-hidden flex flex-col">
            <div class="flex items-center justify-between px-4 py-3 border-b border-gray-700 bg-gray-800">
              <h2 class="font-semibold text-sm">Local Files</h2>
              <button phx-click="refresh_files" class="text-gray-400 hover:text-white">
                <.icon name="hero-arrow-path" class="w-4 h-4" />
              </button>
            </div>
            <div class="flex-1 overflow-y-auto p-2">
              <.file_tree files={@files} expanded={@expanded_dirs} />
            </div>
          </div>

          <div class="h-64 border-t border-gray-700 flex flex-col">
            <div class="px-4 py-3 border-b border-gray-700 bg-gray-800">
              <h2 class="font-semibold text-sm">Agent Channels</h2>
            </div>
            <div class="flex-1 overflow-y-auto p-2">
              <div :if={Enum.empty?(@agents)} class="text-center text-gray-400 py-4 text-sm">
                No available agents
              </div>
              <button
                :for={agent <- @agents}
                phx-click="select_agent"
                phx-value-id={agent.id}
                class={"w-full text-left px-3 py-2 rounded-lg mb-1 transition #{@selected_agent && @selected_agent.id == agent.id && "bg-blue-600" || "bg-gray-800 hover:bg-gray-700"}"}
              >
                <div class="flex items-center justify-between">
                  <span class="font-medium text-sm">{String.capitalize(agent.type)} Agent</span>
                  <span class="text-xs text-gray-400">{short_id(agent.id)}</span>
                </div>
                <p class="text-xs text-gray-400 mt-1 font-mono truncate">{agent.session_key}</p>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:files, :list, required: true)
  attr(:expanded, :any, required: true)

  defp file_tree(assigns) do
    ~H"""
    <div class="space-y-1">
      <.file_item :for={file <- @files} file={file} expanded={@expanded} depth={0} />
    </div>
    """
  end

  attr(:file, :map, required: true)
  attr(:expanded, :any, required: true)
  attr(:depth, :integer, required: true)

  defp file_item(%{file: %{type: :directory}} = assigns) do
    ~H"""
    <div>
      <button
        phx-click="toggle_dir"
        phx-value-path={@file.path}
        class="w-full text-left px-2 py-1 rounded hover:bg-gray-800 flex items-center gap-2"
        style={"padding-left: #{@depth * 12}px"}
      >
        <.icon
          name={(MapSet.member?(@expanded, @file.path) && "hero-folder-open") || "hero-folder"}
          class="w-4 h-4 text-yellow-400"
        />
        <span class="text-sm truncate">{@file.name}</span>
      </button>
      <div :if={MapSet.member?(@expanded, @file.path) && @file.children}>
        <.file_item
          :for={child <- @file.children}
          file={child}
          expanded={@expanded}
          depth={@depth + 1}
        />
      </div>
    </div>
    """
  end

  defp file_item(assigns) do
    ~H"""
    <div
      class="px-2 py-1 rounded hover:bg-gray-800 flex items-center gap-2"
      style={"padding-left: #{@depth * 12 + 24}px"}
    >
      <.icon name={file_icon(@file.name)} class="w-4 h-4 text-gray-400" />
      <span class="text-sm text-gray-300 truncate">{@file.name}</span>
    </div>
    """
  end

  defp file_icon(filename) do
    cond do
      String.ends_with?(filename, ".ex") ->
        "hero-code-bracket"

      String.ends_with?(filename, ".exs") ->
        "hero-code-bracket"

      String.ends_with?(filename, ".md") ->
        "hero-document-text"

      String.ends_with?(filename, ".json") ->
        "hero-code-bracket-square"

      String.ends_with?(filename, ".yml") or String.ends_with?(filename, ".yaml") ->
        "hero-document-text"

      String.ends_with?(filename, ".ts") or String.ends_with?(filename, ".js") ->
        "hero-code-bracket"

      true ->
        "hero-document"
    end
  end

  defp get_file_tree do
    base_path = File.cwd!()

    case File.ls(base_path) do
      {:ok, files} ->
        files
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(&build_file_node(Path.join(base_path, &1), &1))
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp build_file_node(path, name) do
    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        children =
          case File.ls(path) do
            {:ok, files} ->
              files
              |> Enum.reject(&String.starts_with?(&1, "."))
              |> Enum.sort()
              |> Enum.map(&build_file_node(Path.join(path, &1), &1))
              |> Enum.reject(&is_nil/1)

            {:error, _} ->
              []
          end

        %{name: name, path: path, type: :directory, children: children}

      {:ok, %{type: :regular}} ->
        %{name: name, path: path, type: :file}

      _ ->
        nil
    end
  end

  defp load_available_agents do
    all = Agents.list_agents()
    Enum.reject(all, fn agent -> agent.status == "terminated" end)
  end

  defp delegate_to_agent(agent, text) do
    Orchestrator.delegate_task(agent.id, %{"text" => text})
  end

  defp format_result(result) when is_map(result) or is_list(result) do
    Jason.encode!(result, pretty: true)
  end

  defp format_result(result), do: to_string(result)

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0..7)
  defp short_id(_), do: "-"

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
