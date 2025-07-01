ExUnit.start()
{:ok, _} = Application.ensure_all_started(:ex_machina)
{:ok, _} = Finch.start_link(name: Botlead.Finch)
