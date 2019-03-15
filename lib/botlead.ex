defmodule Botlead do
  @moduledoc """
  Botlead application bootstrap.
  """

  use Application

  def start(_type, _args), do: Botlead.Supervisor.start_link()
end
