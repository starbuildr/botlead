defmodule Botlead.TestBot do
  use Botlead.Bot.Server

  @impl true
  def adapter_module, do: Botlead.Bot.Adapter.Telegram

  @impl true
  def client_module, do: Botlead.TestClient

  @impl true
  def is_registered?("reg-" <> _chat_id), do: true
  def is_registered?(_chat_id), do: false

  @impl true
  def process_message_from_the_new_user(_chat_id, _message), do: {:ok, nil}

  @doc """
  Send message to a special listener pid if it's defined.
  """
  def callback(%{listener: listener_pid}, msg) when is_pid(listener_pid) do
    Process.send(listener_pid, msg, [])
    :ok
  end
  def callback(_, _), do: :ok

  @doc """
  Set listener for the bot actions.
  """
  def handle_cast({:set_listener, callback_pid}, state) when is_pid(callback_pid) do
    {:noreply, %{state | listener: callback_pid}}
  end

  @doc """
  Get all bot clients.
  """
  def handle_info({:get_clients, callback_pid}, %{clients: clients} = state) when is_pid(callback_pid) do
    Process.send(callback_pid, {:get_clients, clients}, [])
    {:noreply, state}
  end
end
