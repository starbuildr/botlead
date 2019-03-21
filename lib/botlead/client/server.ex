defmodule Botlead.Client.Server do
  @moduledoc """
  State manager for initialized client connections.
  """

  @doc """
  Custom bot factory
  """
  defmacro __using__(_opts) do
    quote do
      use GenServer
      require Logger

      @behaviour Botlead.Client.Behaviour

      @spec start_link(Keyword.t, String.t, Keyword.t) :: {:ok, pid}
      def start_link(global_opts, chat_id, opts) do
        opts = Keyword.merge(global_opts, opts)
        GenServer.start_link(__MODULE__, %{chat_id: chat_id, opts: opts}, name: instance(chat_id))
      end

      @spec init(map()) :: {:ok, map()} | :error
      def init(%{chat_id: chat_id, opts: opts}) do
        server = instance(chat_id)
        case get_initial_state(chat_id, opts) do
          {:ok, state} ->
            bot_server = Keyword.fetch!(opts, :bot_module)
            Process.send(bot_server, {:attach_client, chat_id, self()}, [])
            new_state = Map.put(state, :__opts__, opts)
            execute_callback(new_state, {:client_started, chat_id, opts})
            {:ok, new_state}
          {:error, error} ->
            Logger.error fn -> "Can't start client server for #{chat_id}, #{inspect(error)}" end
            :error
        end
      end

      @spec terminate(any(), map()) :: :ok
      def terminate(reason, %{chat_id: chat_id, __opts__: opts} = state) do
        Logger.info fn -> "Terminated clinet #{chat_id}, #{inspect(reason)}" end
        bot_server = Keyword.fetch!(opts, :bot_module)
        Process.send(bot_server, {:detach_client, chat_id}, [])
        execute_callback(state, {:client_terminated, reason})
        :ok
      end

      @doc """
      Recieve message from bot.
      """
      def handle_cast({:parse_message, message, opts}, state) do
        conn = message_to_conn(message, state, opts)
        new_state = %{state | conn: conn, scope: conn.scope, path: conn.path}
        execute_callback(new_state, {:parsed_message, conn})
        {:noreply, new_state}
      end

      @doc """
      Message delivery callbacks from bot.
      """
      def handle_cast({:message_delivery_result, action, message}, state) do
        new_state = message_delivered(action, message, state)
        execute_callback(new_state, {:message_delivered, action, message})
        {:noreply, new_state}
      end

      @doc """
      Get call Conn object from session.
      """
      def handle_call({:get_last_conn}, _from, %{conn: conn} = state) do
        {:reply, conn, state}
      end


      @doc """
      Get pid for specific client id.
      """
      @spec get_client_pid(String.t) :: pid | nil
      def get_client_pid(chat_id) do
        server = __MODULE__.instance(chat_id)
        Process.whereis(server)
      end

      @doc """
      Make client connection recieve some new message.
      """
      @spec parse_message(String.t | pid(), map(), Keyword.t) :: :ok
      def parse_message(pid_or_chat_id, message, opts \\ [])
      def parse_message(pid, message, opts) when is_pid(pid) do
        GenServer.cast(pid, {:parse_message, message, opts})
      end
      def parse_message(chat_id, message, opts) when is_binary(chat_id) do
        pid = get_client_pid(chat_id)
        parse_message(pid, message, opts)
      end

      @doc """
      Check if client was started for specific client id.
      """
      @spec is_client_started?(String.t) :: boolean()
      def is_client_started?(chat_id) do
        server = get_client_pid(chat_id)
        server != nil and Process.alive?(server)
      end

      @doc """
      Start client instance for chat id.
      """
      @spec connect(pid(), String.t, Keyword.t) :: {:ok, pid} | :error
      def connect(bot_server, chat_id, opts \\ []) do
        Botlead.Client.Supervisor.start_client(__MODULE__, bot_server, chat_id, opts)
      end

      @doc """
      Remove client instance for chat id.
      """
      @spec disconnect(pid(), String.t) :: :ok | :error
      def disconnect(bot_server, chat_id) do
        pid = get_client_pid(chat_id)
        if pid do
          Botlead.Client.Supervisor.remove_client(bot_server, pid, chat_id)
        else
          :ok
        end
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
