defmodule Botlead.TestClient do
  use Botlead.Client.Server

  @impl true
  def router, do: Botlead.TestRouter

  @impl true
  def instance(chat_id), do: String.to_atom("client_#{chat_id}")

  @impl true
  def get_initial_state(chat_id, opts) do
    user = get_user_by_chat_id(chat_id)

    %{
      chat_id: chat_id,
      user: user,
      listener: Keyword.get(opts, :listener),
      conn: nil,
      path: nil,
      scope: nil
    }
  end

  @impl true
  def message_to_conn(message, state, opts) do
    case router().match_message(message, state.path, state.scope, opts) do
      %{code: 200} = conn ->
        conn

      conn ->
        Logger.warning(fn -> "Client ignores message #{inspect(message)}}" end)
        conn
    end
  end

  @impl true
  def message_delivered(_action, _message, state) do
    state
  end

  def get_user_by_chat_id(chat_id) when is_binary(chat_id) do
    %{"telegram_chat_id" => chat_id}
  end

  @doc """
  Send message to a special listener pid if it's defined.
  """
  def callback(%{listener: listener_pid}, msg) when is_pid(listener_pid) do
    Process.send(listener_pid, msg, [])
    :ok
  end

  def callback(_, _), do: :ok
end
