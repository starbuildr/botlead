defmodule Botlead.Factory do
  use ExMachina

  def telegram_message_factory do
    %Nadia.Model.Update{
      update_id: sequence(:update_id, &"update#{&1}"),
      message: %{
        chat: %{
          id: sequence(:chat_id, &"chat#{&1}"),
          text: "test"
        }
      }
    }
  end
end
