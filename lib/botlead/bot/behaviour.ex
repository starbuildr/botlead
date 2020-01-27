defmodule Botlead.Bot.Behaviour do
  @moduledoc """
  Callback which require implementation by custom bot servers.
  """

  @doc """
  Module to use for low-level operations on chat platform.
  """
  @callback adapter_module() :: module()

  @doc """
  Module to use for client connections to this bot.
  """
  @callback client_module() :: module()

  @doc """
  Check if user was registered for the related chat_id.
  """
  @callback is_registered?(String.t()) :: boolean()

  @doc """
  Callback for handling messages from unknown clients.
  """
  @callback process_message_from_the_new_user(String.t(), map()) :: {:ok, any()} | {:error, any()}
end
