defmodule Botlead.Supervisor do
  @moduledoc """
  Supervisor to keep track of bot server and connected clients.
  """

  use Supervisor

  @spec start_link() :: {:ok, pid}
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec init([]) :: {:ok, tuple()}
  def init([]) do
    config = Application.get_env(:botlead, __MODULE__) |> Keyword.fetch!(:bots)
    children =
      Enum.reduce config, [], fn(child_config, children) ->
        case child_config do
          bot_module when is_atom(bot_module) ->
            opts = [bot_module: bot_module, client_module: bot_module.client_module()]
            client_supervisor = supervisor(Botlead.Client.Supervisor, [opts])
            bot_worker = worker(bot_module, [opts])
            [client_supervisor | [bot_worker | children]]
          _ ->
            children
        end
      end
    supervise(children, strategy: :one_for_one)
  end
end
