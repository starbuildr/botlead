defmodule Botlead.Factory do
  use ExMachina

  def telegram_message_factory do
    %Telegex.Type.Update{
      update_id: sequence(:update_id, &"update#{&1}"),
      message: %Telegex.Type.Message{
        chat: %Telegex.Type.Chat{
          id: sequence(:chat_id, &"chat#{&1}"),
          type: "supergroup",
          title: "Mock chat"
        },
        message_id: sequence(:message_id, &"msg#{&1}"),
        text: "test",
        date: :os.system_time(:seconds)
      }
    }
  end
end
