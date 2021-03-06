defmodule Botlead.TestRouter do
  use GenRouter
  alias Botlead.Controller.TestController

  pipeline :authed do
    plug(Botlead.Plug.TestPlug)
  end

  scope :default, "/" do
    pipe_through([:authed])

    match("/", TestController, :test1)
    match("/test1", TestController, :test1)
    match("/test2", TestController, :test2)
  end

  scope :test_scope, "/stest" do
    pipe_through([:authed])

    match("/", TestController, :test3)
  end

  scope :test_complex_scope, "/stest/complex" do
    pipe_through([:authed])

    match("/", TestController, :test2)
  end

  match("*", TestController, :not_found)

  @impl true
  def match_message(router_module, message, path, scope, assigns, opts) do
    conn =
      GenRouter.Conn.build(router_module, %{
        path: path,
        params: %{message: message},
        assigns: assigns,
        scope: scope
      })

    router_module.do_match(conn, opts)
  end

  @impl true
  def deliver(conn, _view, _template, _params, _opts) do
    conn
  end
end
