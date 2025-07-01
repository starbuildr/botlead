# This file is responsible for configuring your application
import Config

config :telegex,
  caller_adapter: Finch,
  token: {:system, "TELEGRAM_BOT_TOKEN"}

config :botlead, Botlead.Bot.Adapter.Telegram,
  poll_delay: 600,
  poll_limit: 100,
  #use_webhook: [{Botlead.TestBot, "URL", 4000}]
  sendbox_message_send: true

config :botlead, Botlead.Supervisor,
  bots: [Botlead.TestBot]
