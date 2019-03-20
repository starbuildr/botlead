defmodule Botlead.Bot.Server do
  @moduledoc """
  Boilerplate for custom bot server configuration
  """

  require Logger

  @doc """
  Relay message to client
  """
  def relay_msg_to_client(chat_id, message, clients, client_module, bot_server, is_registered?, process_message_from_the_new_user) do
    case Map.get(clients, chat_id) do
      pid when is_pid(pid) ->
        client_module.parse_message(pid, message)
        :ok
      _ ->
        with \
          true <- is_registered?.(chat_id),
          {false, _} <- {client_module.is_client_started?(chat_id), chat_id},
          {:ok, pid} <- client_module.connect(bot_server, chat_id)
        do
          Process.send(__MODULE__, {:attach_client, chat_id, pid}, [])
          client_module.parse_message(pid, message)
        else
          false ->
            with \
              {:ok, _} <- process_message_from_the_new_user.(chat_id, message),
              {:ok, pid} <- client_module.connect(bot_server, chat_id)
            do
              if Process.whereis(__MODULE__) do
                Process.send(__MODULE__, {:attach_client, chat_id, pid}, [])
              else
                if System.get_env("MIX_ENV") !== "test" do
                  Logger.error fn -> "Bot server is dead and can't attach client" end
                end
              end
              client_module.parse_message(pid, message)
            else
              {:error, changeset} ->
                Logger.error fn -> "Unable to register the new client: #{inspect(changeset)}" end
              error ->
                Logger.error fn -> "Unable to connect the new client: #{inspect(error)}" end
            end
          {true, chat_id} ->
            pid = client_module.get_client_pid(chat_id)
            Process.send(__MODULE__, {:attach_client, chat_id, pid}, [])
            client_module.parse_message(pid, message)
          _ ->
            Logger.error fn -> "Unable to start client #{inspect(chat_id)} and relay: #{inspect(message)}" end
        end
        :ok
    end
  end

  @doc """
  Custom bot factory
  """
  defmacro __using__(_opts) do
    quote do
      use GenServer
      require Logger

      @behaviour Botlead.Bot.Behaviour

      @doc false
      @spec start_link(Keyword.t) :: {:ok, pid}
      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc """
      Initialise state of bot server according to adapter config.
      """
      @spec init(Keyword.t) :: {:ok, map()}
      def init(_opts) do
        state =
          %{
            processed_messages: [],
            last_update: 0,
            clients: %{},
            listener: nil
          }

        case adapter_module().init() do
          :ok ->
            {:ok, state}
          {:poll, poll_delay, poll_limit} ->
            Logger.info fn -> "Starting polling of Telegram bot updates..." end
            timer = Process.send_after(__MODULE__, {:get_updates}, poll_delay)
            state = Map.merge(state, %{poll_timer: timer, poll_delay: poll_delay, poll_limit: poll_limit})
            {:ok, state}
        end
      end

      @doc """
      Post message to platform by chat id.
      """
      def handle_cast({:send_message, chat_id, text, opts}, %{clients: clients} = state) do
        client_pid = Map.get(clients, chat_id)
        adapter_module().send_message(chat_id, text, client_pid, opts)
        {:noreply, state}
      end

      @doc """
      Edit previously posted message.
      """
      def handle_cast({:edit_message, chat_id, message_id, text, opts}, %{clients: clients} = state) do
        client_pid = Map.get(clients, chat_id)
        adapter_module().edit_message(chat_id, message_id, text, client_pid, opts)
        {:noreply, state}
      end

      @doc """
      Delete previously posted message.
      """
      def handle_cast({:delete_message, chat_id, message_id, opts}, %{clients: clients} = state) do
        client_pid = Map.get(clients, chat_id)
        adapter_module().delete_message(chat_id, message_id, client_pid, opts)
        {:noreply, state}
      end

      @doc """
      Fetch updates from bot log.
      """
      def handle_info({:get_updates}, %{
        poll_timer: timer,
        poll_limit: poll_limit,
        poll_delay: poll_delay,
        last_update: last_update
      } = state) do
        if (Process.read_timer(timer) == false) do
          new_state =
            case adapter_module().get_updates(last_update, poll_limit) do
              {:ok, messages} ->
                Process.send(self(), {:process_updates, messages}, [])
                state
              :error ->
                state
            end

          timer = Process.send_after(__MODULE__, {:get_updates}, poll_delay)
          {:noreply, %{new_state | poll_timer: timer}}
        else
          {:noreply, state}
        end
      end

      @doc """
      Relay message to client.

      Can use either a customly defined `relay_msg_to_client/3`
      or will fallback to a default one.
      """
      def handle_info({:relay_msg_to_client, chat_id, message}, %{clients: clients} = state) do
        if Keyword.has_key?(__MODULE__.__info__(:functions), :relay_msg_to_client) do
          apply(__MODULE__, :relay_msg_to_client, [chat_id, message, clients])
        else
          Botlead.Bot.Server.relay_msg_to_client(
            chat_id,
            message,
            clients,
            client_module(),
            self(),
            &is_registered?/1,
            &process_message_from_the_new_user/2
          )
        end
        {:noreply, state}
      end

      @doc """
      Handle updates from bot
      """
      def handle_info({:process_updates, messages}, %{processed_messages: old_messages} = state) do
        {:ok, new_updates, last_update, cmds} = adapter_module().process_messages(messages, old_messages)
        if length(new_updates) > 0 do
          Enum.each cmds, fn(cmd) ->
            case cmd do
              {:relay_msg_to_client, chat_id, message} = cmd ->
                Process.send(self(), cmd, [])
              {:restart_client, chat_id} = cmd ->
                Process.send(self(), cmd, [])
              _ ->
                :ok
            end
          end
          execute_callback(state, {:processed_updates, new_updates})
          {:noreply, %{state | processed_messages: old_messages ++ new_updates, last_update: last_update}}
        else
          execute_callback(state, {:processed_updates, new_updates})
          {:noreply, state}
        end
      end

      @doc """
      Restart client session
      """
      def handle_info({:restart_client, chat_id, opts}, state) when is_integer(chat_id) or is_binary(chat_id) do
        :ok = client_module().disconnect(self(), chat_id)
        {:ok, new_pid} = client_module().connect(self(), chat_id, opts)
        execute_callback(state, {:restarted_client, chat_id, new_pid})
        {:noreply, state}
      end

      @doc """
      Attach client to bot
      """
      def handle_info({:attach_client, chat_id, pid}, %{clients: clients} = state)
      when is_pid(pid) and (is_integer(chat_id) or is_binary(chat_id)) do
        execute_callback(state, {:attached_client, chat_id, pid})
        {:noreply, %{state | clients: Map.put(clients, chat_id, pid)}}
      end

      @doc """
      Detach client from bot
      """
      def handle_info({:detach_client, chat_id}, %{clients: clients} = state)
      when is_integer(chat_id) or is_binary(chat_id) do
        execute_callback(state, {:detached_client, chat_id})
        {:noreply, %{state | clients: Map.drop(clients, [chat_id])}}
      end

      @doc """
      Send the new message by Bot.
      """
      @spec send_message(String.t, String.t, Keyword.t) :: :ok
      def send_message(telegram_chat_id, text, opts \\ []) do
        message = {:send_message, telegram_chat_id, text, opts}
        GenServer.cast(__MODULE__, message)
      end

      @doc """
      Edit existing message by Bot.
      """
      @spec edit_message(String.t, String.t, String.t, Keyword.t) :: :ok
      def edit_message(telegram_chat_id, message_id, text, opts \\ []) do
        message = {:edit_message, telegram_chat_id, message_id, text, opts}
        GenServer.cast(__MODULE__, message)
      end

      @doc """
      Delete existing message by Bot.
      """
      @spec delete_message(String.t, String.t, Keyword.t) :: :ok
      def delete_message(telegram_chat_id, message_id, opts \\ []) do
        message = {:delete_message, telegram_chat_id, message_id, opts}
        GenServer.cast(__MODULE__, message)
      end

      @doc """
      Send message to a special listener pid if it's defined.
      """
      def execute_callback(state, msg) do
        if Keyword.has_key?(__MODULE__.__info__(:functions), :callback) do
          callback(state, msg)
        else
          :ok
        end
      end
    end
  end
end
