defmodule Botlead.Supervisor do
  @moduledoc """
  Supervisor to keep track of bot server and connected clients.
  """

  use Supervisor

  @spec init([]) :: :ignore | {:error, any()} | {:ok, pid()}
  def init([]) do
    config = Application.get_env(:botlead, __MODULE__) |> Keyword.fetch!(:bots)

    children =
      Enum.reduce(config, [], fn child_config, children ->
        case child_config do
          bot_module when is_atom(bot_module) ->
            opts = [bot_module: bot_module, client_module: bot_module.client_module()]
            client_supervisor = {Botlead.Client.Supervisor, opts}
            bot_worker = {bot_module, opts}
            [client_supervisor | [bot_worker | children]]

          _ ->
            children
        end
      end)

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts) |> IO.inspect()
  end
end
