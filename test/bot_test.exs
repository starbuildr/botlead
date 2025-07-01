defmodule Botlead.BotTest do
  use ExUnit.Case
  use ExVCR.Mock
  import Botlead.Factory

  setup do
    GenServer.cast(Botlead.TestBot, {:set_listener, self()})
    ExVCR.Config.cassette_library_dir("support/fixture/vcr_cassettes")
    :ok
  end

  describe "bot API" do
    test "send message" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      text = message.message.text
      {:ok, _pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id, listener: self())
      Botlead.TestBot.send_message(chat_id, text)
      assert_receive {:message_delivered, :sent, :ok}
    end

    test "send message as structure" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      text = message.message.text

      msg = %Botlead.Message{
        content: text
      }

      {:ok, _pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id, listener: self())
      Botlead.TestBot.send_message(chat_id, msg)
      assert_receive {:message_delivered, :sent, :ok}
    end

    test "edit message" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      text = message.message.text
      update_id = message.update_id
      {:ok, _pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id, listener: self())
      Botlead.TestBot.edit_message(chat_id, message.update_id, text)
      assert_receive {:message_delivered, :edited, ^update_id}
    end

    test "delete message" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      update_id = message.update_id
      {:ok, _pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id, listener: self())
      Botlead.TestBot.delete_message(chat_id, update_id)
      assert_receive {:message_delivered, :deleted, ^update_id}
    end
  end

  describe "bot server" do
    test "is alive" do
      pid = Process.whereis(Botlead.TestBot)
      assert Process.alive?(pid)
    end

    test "registers clients automatically" do
      messages = build_list(5, :telegram_message)
      chat_ids = Enum.map(messages, & &1.message.chat.id)
      Process.send(Botlead.TestBot, {:process_updates, messages}, [])

      Enum.each(chat_ids, fn chat_id ->
        assert_receive {:attached_client, ^chat_id, _pid}
      end)
    end

    test "client can be restarted, new process will be spawned" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      {:ok, pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id, listener: self())
      assert_receive {:client_started, ^chat_id, _opts}

      Process.send(Botlead.TestBot, {:restart_client, chat_id, listener: self()}, [])
      assert_receive {:restarted_client, ^chat_id, new_pid}
      refute pid === new_pid
      assert_receive {:client_started, ^chat_id, _opts}
    end

    test "attach client process in case it was started" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      {:ok, _pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id)
      Process.send(Botlead.TestBot, {:get_clients, self()}, [])
      assert_receive {:get_clients, clients}
      client_pid = Map.get(clients, chat_id)
      assert client_pid
    end

    test "deattach client process in case it was stopped" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      {:ok, _pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id)
      Botlead.TestClient.disconnect(Botlead.TestBot, chat_id)
      Process.send(Botlead.TestBot, {:get_clients, self()}, [])
      assert_receive {:get_clients, clients}
      client_pid = Map.get(clients, chat_id)
      refute client_pid
    end

    test "automatically re-attach client process after it's unexpected restart" do
      message = build(:telegram_message)
      chat_id = message.message.chat.id
      {:ok, pid} = Botlead.TestClient.connect(Botlead.TestBot, chat_id)
      Process.exit(pid, :kill)
      :timer.sleep(10)
      Process.send(Botlead.TestBot, {:get_clients, self()}, [])
      assert_receive {:get_clients, clients}
      client_pid = Map.get(clients, chat_id)
      refute pid === client_pid
      refute Process.alive?(pid)
      assert Process.alive?(client_pid)
    end
  end
end
