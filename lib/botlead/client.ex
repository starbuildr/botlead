defmodule Botlead.Client do
  @moduledoc """
  Use this module to connect existing client to chat session.
  """

  @doc """
  Make client connection recieve some new message.
  """
  @spec parse_message(pid(), map(), Keyword.t) :: :ok
  def parse_message(pid, message, opts \\ []) when is_pid(pid) do
    GenServer.cast(pid, {:parse_message, message, opts})
  end
  @spec parse_message(module(), String.t, map(), Keyword.t) :: :ok
  def parse_message(client_module, chat_id, message, opts) do
    pid = get_client_pid(client_module, chat_id)
    parse_message(pid, message, opts)
  end


  @doc """
  Check if client was started for specific client id.
  """
  @spec is_client_started?(module(), String.t) :: boolean()
  def is_client_started?(client_module, chat_id) do
    server = get_client_pid(client_module, chat_id)
    server != nil and Process.alive?(server)
  end

  @doc """
  Get pid for specific client id.
  """
  @spec get_client_pid(module(), String.t) :: pid | nil
  def get_client_pid(client_module, chat_id) do
    server = client_module.instance(chat_id)
    Process.whereis(server)
  end


  @doc """
  Start client instance for chat id.
  """
  defdelegate connect(client_module, bot_server, chat_id), to: Botlead.Client.Supervisor, as: :start_client
  defdelegate connect(client_module, bot_server, chat_id, opts), to: Botlead.Client.Supervisor, as: :start_client

  @doc """
  Remove client instance for chat id.
  """
  @spec disconnect(module(), pid(), String.t) :: :ok | :error
  def disconnect(client_module, bot_server, chat_id) do
    pid = get_client_pid(client_module, chat_id)
    Botlead.Client.Supervisor.remove_client(bot_server, pid, chat_id)
  end
end
