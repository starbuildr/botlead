defmodule Botlead.Client.Behaviour do
  @moduledoc """
  Callback which require implementation by custom bot clients.
  """

  @type state :: map()
  @type message :: map()
  @type delivery_action :: :sent | :edited | :deleted

  @doc """
  Module for message routing.
  """
  @callback router() :: module()

  @doc """
  Name generator for client session servers.
  """
  @callback instance(String.t()) :: atom()

  @doc """
  Default state for client session.
  """
  @callback get_initial_state(String.t(), Keyword.t()) :: state

  @doc """
  Transform new message from bot into connection object.
  The place to put routing business logic.
  """
  @callback message_to_conn(message, state, Keyword.t()) :: GenRouter.Conn.t()

  @doc """
  Callback for handling message delivery, replaces the current state.
  """
  @callback message_delivered(delivery_action, message, state) :: state
end
