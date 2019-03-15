defmodule Botlead.Plug.TestPlug do
  @doc false
  def call(%{assigns: %{authorized: true}} = conn, _opts), do: conn
  def call(conn, _opts), do: %{conn | code: 403}
end
