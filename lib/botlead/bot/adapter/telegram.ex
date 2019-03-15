defmodule Botlead.Bot.Adapter.Telegram do
  @moduledoc """
  Implementation business logic for Bot server for Telegram platform.
  """

  require Logger

  @type cmd :: {:relay_msg_to_client, String.t, map()} | {:restart_client, String.t}
  @type parsed_message :: :no_parser | :invalid_message | cmd

  @retry_delay 500

  @doc """
  Start Telegram process either by webhook or with periodical config.
  """
  @spec init() :: :ok | {:poll, integer(), integer()}
  def init do
    if config(:use_webhook, false) do
      webhook = config!(:webhook_url)
      Logger.info fn -> "Setting Telegram postback webhook to: #{webhook}" end
      Nadia.set_webhook(url: webhook)
      :ok
    else
      poll_delay = config!(:poll_delay)
      poll_limit = config!(:poll_limit)
      {:poll, poll_delay, poll_limit}
    end
  end

  @doc """
  Deliver message to Telegram with successful delivery postback.
  """
  @spec send_message(String.t, String.t, pid() | nil, Keyword.t) :: :ok
  def send_message(chat_id, text, client_pid, opts) do
    with \
      false <- config(:sendbox_message_send, false),
      {:ok, result} <- Nadia.send_message(chat_id, text, opts)
    do
      case client_pid do
        nil ->
          :ok
        pid ->
          GenServer.cast(pid, {:message_delivered, result})
      end
    else
      true ->
        Logger.info fn -> "No chat messages send in a sandbox mode!" end
        :ok
      {:error, %Nadia.Model.Error{reason: "Please wait a little"}} ->
        Logger.warn fn -> "Telegram bot message retry send_message!" end
        :timer.sleep(@retry_delay)
        send_message(chat_id, text, client_pid, opts)
    end
  end

  @doc """
  Edit existing message by it's id.
  """
  @spec edit_message(String.t, String.t, String.t, Keyword.t) :: :ok
  def edit_message(chat_id, message_id, text, opts) do
    case Nadia.edit_message_text(chat_id, message_id, nil, text, opts) do
      {:ok, _result} ->
        :ok
      {:error, %Nadia.Model.Error{reason: "Please wait a little"}} ->
        Logger.warn fn -> "Telegram bot message retry edit_message!" end
        :timer.sleep(@retry_delay)
        edit_message(chat_id, message_id, text, opts)
    end
  end

  @doc """
  Delete existing message by it's id.
  """
  @spec delete_message(String.t, String.t, Keyword.t) :: :ok
  def delete_message(chat_id, message_id, opts) do
    case Nadia.API.request("deleteMessage", [chat_id: chat_id, message_id: message_id]) do
      :ok ->
        :ok
      {:error, %Nadia.Model.Error{reason: "Please wait a little"}} ->
        Logger.warn fn() -> "Telegram bot message retry delete_message!" end
        :timer.sleep(@retry_delay)
        delete_message(chat_id, message_id, opts)
    end
  end

  @doc """
  Poll all updates from Telegram server.
  """
  @spec get_updates(integer(), integer()) :: {:ok, [map()]} | :error
  def get_updates(last_update, poll_limit) do
    opts = [limit: poll_limit]
    opts = if last_update > 0, do: Keyword.put(opts, :offset, last_update), else: opts
    case Nadia.get_updates(opts) do
      {:ok, messages} ->
        {:ok, messages}
      issues ->
        Logger.warn fn -> "Telegram polling issues #{inspect(issues)}" end
        :error
    end
  end

  @doc """
  Parse messages recieved from Telegram server.
  """
  @spec process_messages([map()], [integer()]) :: {:ok, [integer()], integer(), [parsed_message]}
  def process_messages(messages, old_message_ids) do
    {new_updates, cmds} =
      messages
      |> Enum.filter(&(&1.update_id not in old_message_ids))
      |> Enum.map(&parse_message/1)
      |> Enum.unzip()
    last_update = Enum.max(new_updates)
    {:ok, new_updates, last_update, cmds}
  end

  @doc """
  Read module config value with default as fallback.
  """
  @spec config(atom(), any()) :: any()
  def config(key, default \\ nil) do
    Application.get_env(:botlead, __MODULE__)
    |> Keyword.get(key, default)
  end

  @doc """
  Read module config value, raise if not configured.
  """
  @spec config!(atom()) :: any() | no_return
  def config!(key) do
    Application.get_env(:botlead, __MODULE__)
    |> Keyword.fetch!(key)
  end


  # Start Telegram client if needed
  @spec parse_message(map()) :: {integer(), parsed_message}
  defp parse_message(%Nadia.Model.Update{message: %{chat: %{id: chat_id}, text: "/restart"}, update_id: update_id}) do
    {update_id, {:restart_client, chat_id, []}}
  end
  defp parse_message(%Nadia.Model.Update{message: %{chat: %{id: chat_id}}, update_id: update_id} = message) do
    {update_id, {:relay_msg_to_client, chat_id, message}}
  end
  defp parse_message(%Nadia.Model.Update{callback_query: %{message: %{chat: %{id: chat_id}}}, update_id: update_id} = message) do
    {update_id, {:relay_msg_to_client, chat_id, message}}
  end
  defp parse_message(%{update_id: update_id} = message) when is_integer(update_id) do
    Logger.info fn -> "Ignore message: #{inspect(message)}" end
    {update_id, :no_parser}
  end
  defp parse_message(message) do
    Logger.warn fn -> "Invalid message: #{inspect(message)}" end
    {0, :invalid_message}
  end
end
