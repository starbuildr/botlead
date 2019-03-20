defmodule Botlead.ClientTest do
  use ExUnit.Case
  use ExVCR.Mock
  import Botlead.Factory

  setup do
    GenServer.cast(Botlead.TestBot, {:set_listener, self()})
    ExVCR.Config.cassette_library_dir("support/fixture/vcr_cassettes")
    :ok
  end

  describe "client server" do
    test "recieves the relayed messages from bot" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      {:ok, _pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id, listener: self())
      Process.send(Botlead.TestBot, {:process_updates, [message]}, [])
      assert_receive {:parsed_message, %GenRouter.Conn{} = conn}
      assert conn.params.message === message
    end

    test "automatically starts new process on a new message if needed" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      refute Botlead.TestClient.is_client_started?(chat_id)
      Process.send(Botlead.TestBot, {:process_updates, [message]}, [])
      assert_receive {:attached_client, ^chat_id, pid}
      assert Botlead.TestClient.is_client_started?(chat_id)
      conn = GenServer.call(pid, {:get_last_conn})
      assert conn.params.message === message
    end
  end
end
