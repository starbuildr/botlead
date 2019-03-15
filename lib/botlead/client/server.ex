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
      def handle_cast({:message_delivered, message}, state) do
        new_state = message_delivered(message, state)
        execute_callback(new_state, {:message_delivered_callback, message})
        {:noreply, new_state}
      end

      @doc """
      Get call Conn object from session.
      """
      def handle_call({:get_last_conn}, _from, %{conn: conn} = state) do
        {:reply, conn, state}
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
