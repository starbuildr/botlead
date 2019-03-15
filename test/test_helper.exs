config = [bots: [Botlead.TestBot]]
Application.put_env(:botlead, Botlead.Supervisor, config)
Botlead.start([], [])

ExUnit.start()
{:ok, _} = Application.ensure_all_started(:ex_machina)
