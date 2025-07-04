defmodule Botlead.Bot.Adapter.Telegram do
  @moduledoc """
  Implementation business logic for Bot server for Telegram platform.
  """

  use Telegex.Hook.GenHandler
  require Logger

  @type cmd :: {:relay_msg_to_client, String.t(), map()} | {:restart_client, String.t()}
  @type parsed_message :: :no_parser | :invalid_message | cmd

  @retry_delay 500

  @impl true
  def on_boot do
    if config(:use_webhook, false) do
      {_bot_name, webhook, port} = config!(:use_webhook) |> List.first()
      Logger.info(fn -> "Setting Telegram postback webhook to: #{webhook}" end)

      {:ok, true} = Telegex.delete_webhook()
      {:ok, true} = Telegex.set_webhook(url: webhook)
      %Telegex.Hook.Config{server_port: port}
    else
      {:ok, true} = Telegex.delete_webhook()
      poll_delay = config!(:poll_delay)
      poll_limit = config!(:poll_limit)
      %Telegex.Polling.Config{limit: poll_limit, interval: poll_delay}
    end
  end

  @impl true
  def on_update(update) do
    {bot_name, _webhook, _port} = config!(:use_webhook) |> List.first()
    Process.send(bot_name, {:process_updates, update}, [])
    :ok
  end

  @doc false
  def init do
    if config(:use_webhook, false) do
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
  @spec send_message(String.t() | integer(), String.t(), pid() | nil, Keyword.t()) :: :ok
  def send_message(chat_id, text, client_pid, opts) do
    with false <- config(:sendbox_message_send, false),
         {:ok, result} <- Telegex.send_message(chat_id, text, opts) do
      maybe_notify_msg_result(client_pid, {:sent, result})
    else
      true ->
        Logger.info(fn -> "No chat messages sent in a sandbox mode!" end)
        maybe_notify_msg_result(client_pid, {:sent, :ok})

      {:error, %Telegex.Error{description: "Please wait a little"}} ->
        Logger.warning(fn -> "Telegram bot message retry send_message!" end)
        :timer.sleep(@retry_delay)
        send_message(chat_id, text, client_pid, opts)

      response ->
        Logger.warning(fn -> "Unexpected response from Telegex client #{inspect(response)}" end)
        :ok
    end
  end

  @doc """
  Edit existing message by it's id.
  """
  @spec edit_message(String.t(), String.t(), String.t(), pid() | nil, Keyword.t()) :: :ok
  def edit_message(chat_id, message_id, text, client_pid, opts) do
    unless config(:sendbox_message_send, false) do
      case Telegex.edit_message_text(text, [chat_id: chat_id, message_id: message_id] ++ opts) do
        {:ok, result} ->
          maybe_notify_msg_result(client_pid, {:edited, result})

        {:error, %Telegex.Error{description: "Please wait a little"}} ->
          Logger.warning(fn -> "Telegram bot message retry edit_message!" end)
          :timer.sleep(@retry_delay)
          edit_message(chat_id, message_id, text, client_pid, opts)
      end
    else
      Logger.info(fn -> "No chat messages are edited in a sandbox mode!" end)
      maybe_notify_msg_result(client_pid, {:edited, message_id})
    end
  end

  @doc """
  Delete existing message by it's id.
  """
  @spec delete_message(String.t(), String.t(), pid() | nil, Keyword.t()) :: :ok
  def delete_message(chat_id, message_id, client_pid, opts) do
    unless config(:sendbox_message_send, false) do
      case Telegex.delete_message(chat_id, message_id) do
        :ok ->
          maybe_notify_msg_result(client_pid, {:deleted, message_id})

        {:error, %Telegex.Error{description: "Please wait a little"}} ->
          Logger.warning(fn -> "Telegram bot message retry delete_message!" end)
          :timer.sleep(@retry_delay)
          delete_message(chat_id, message_id, client_pid, opts)
      end
    else
      Logger.info(fn -> "No chat messages are deleted in a sandbox mode!" end)
      maybe_notify_msg_result(client_pid, {:deleted, message_id})
    end
  end

  @doc """
  Poll all updates from Telegram server.
  """
  @spec get_updates(integer(), integer()) :: {:ok, [map()]} | :error
  def get_updates(last_update, poll_limit) do
    opts = [limit: poll_limit]
    opts = if last_update > 0, do: Keyword.put(opts, :offset, last_update), else: opts

    case Telegex.get_updates(opts) do
      {:ok, messages} ->
        {:ok, messages}

      issues ->
        Logger.warning(fn -> "Telegram polling issues #{inspect(issues)}" end)
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

    last_update = Enum.max(new_updates, fn -> nil end)
    {:ok, new_updates, last_update, cmds}
  end

  @doc """
  Create Telegex client option specification for message response.
  """
  @spec msg_to_opts(%Botlead.Message{}, Keyword.t()) :: Keyword.t()
  def msg_to_opts(%Botlead.Message{} = msg, msg_opts \\ []) do
    Enum.reduce(Map.from_struct(msg), msg_opts, fn {key, value}, msg_opts ->
      case {key, value} do
        {:parse_mode, value} when value != nil ->
          Keyword.put(msg_opts, :parse_mode, value)

        {:inline_keyboard, value} when value != nil ->
          Keyword.put(msg_opts, :reply_markup, %{inline_keyboard: value})

        _ ->
          msg_opts
      end
    end)
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
  defp parse_message(%Telegex.Type.Update{
         message: %{chat: %{id: chat_id}, text: "/restart"},
         update_id: update_id
       }) do
    {update_id, {:restart_client, "#{chat_id}", []}}
  end

  defp parse_message(
         %Telegex.Type.Update{message: %{chat: %{id: chat_id}}, update_id: update_id} = message
       ) do
    {update_id, {:relay_msg_to_client, "#{chat_id}", message}}
  end

  defp parse_message(
         %Telegex.Type.Update{
           callback_query: %{message: %{chat: %{id: chat_id}}},
           update_id: update_id
         } = message
       ) do
    {update_id, {:relay_msg_to_client, "#{chat_id}", message}}
  end

  defp parse_message(%{update_id: update_id} = message) when is_integer(update_id) do
    Logger.info(fn -> "Ignore message: #{inspect(message)}" end)
    {update_id, :no_parser}
  end

  defp parse_message(message) do
    Logger.warning(fn -> "Invalid message: #{inspect(message)}" end)
    {0, :invalid_message}
  end

  @spec maybe_notify_msg_result(pid() | nil, {Botlead.Client.Behaviour.delivery_action(), any()}) ::
          :ok
  defp maybe_notify_msg_result(pid, {action, result}) when is_pid(pid) do
    GenServer.cast(pid, {:message_delivery_result, action, result})
  end

  defp maybe_notify_msg_result(_, _), do: :ok
end
