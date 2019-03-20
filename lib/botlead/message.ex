defmodule Botlead.Message do
  @moduledoc """
  Standart message send by bot
  """

  @type keyboard :: [[map()]]

  defstruct [:content, :inline_keyboard, :parse_mode]
end
