defmodule Botlead.Client.Supervisor do
  @moduledoc """
  Supervisor to keep track of the initialized client sessions.
  """

  use DynamicSupervisor
  require Logger

  @spec start_link(Keyword.t()) :: {:ok, pid}
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec init(Keyword.t()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(opts) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [opts])
  end

  @spec start_client(module(), atom() | pid(), String.t(), Keyword.t()) :: {:ok, pid} | :error
  def start_client(client_module, bot_server, chat_id, opts \\ []) when is_binary(chat_id) do
    spec = %{
      id: client_module,
      start: {client_module, :start_link, [chat_id, opts]},
      shutdown: 5_000,
      restart: :transient,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Process.send(bot_server, {:attach_client, chat_id, pid}, [])
        {:ok, pid}

      {:ok, pid, _info} ->
        Process.send(bot_server, {:attach_client, chat_id, pid}, [])
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.warning(fn -> "Client process #{chat_id} was already started" end)
        {:ok, pid}

      error ->
        Logger.error(fn -> "Can't start client process #{chat_id}, #{inspect(error)}" end)
        :error
    end
  end

  @spec remove_client(atom() | pid(), atom() | pid(), String.t()) :: :ok | :error
  def remove_client(bot_server, pid, chat_id) when is_pid(pid) and is_binary(chat_id) do
    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok ->
        Process.send(bot_server, {:detach_client, chat_id}, [])
        :ok

      error ->
        Logger.error(fn -> "Can't stop client process #{chat_id}, #{inspect(error)}" end)
        :error
    end
  end

  def remove_client(bot_server, instance, chat_id) when is_binary(chat_id) do
    case Process.whereis(instance) do
      pid when is_pid(pid) ->
        remove_client(bot_server, pid, chat_id)

      _ ->
        Logger.error(fn -> "Can't stop client process #{chat_id}" end)
        :error
    end
  end
end
