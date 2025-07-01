# Botlead

[HexDocs](https://hexdocs.pm/botlead)

The main motivation for creating this library was lack of easy to use tools to define
sessions for chat bots. The use of sessions allows us to add aditional authorization
mechanisms to improve general security of your communication with bot and define some
scope for the current conversion. 

Botlead defines two core abstractions: `Bot` and `Client`.

`Bot` - is a process which runs your bot on some platform (e.g. Telegram). It manages
messages and redirect the relevant ones to the end clients.

`Client` - is a process to store the client session which recieves messages send by bot
and do the proper routing, by the rules defined in router specification. We use 
[GenRouter](https://hexdocs.pm/gen_router) as our default routing library.

## Installation

Add `botlead` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:botlead, "~> 0.2"}
  ]
end
```

## Configuration

Add your bot into `:botlead` configuration:

```
config :botlead, Botlead.Supervisor,
  bots: [
    MyApp.Bot
  ]
```

### Botlead.Bot.Adapter.Telegram

* `use_webhook` - add URL for your webserver to get Telegram updates as postbacks instead of polling;
* `poll_delay` - millisecond delay for polling updates from Telegram;
* `poll_limit` - maximum amount of update records which will be queried in one request;
* `sendbox_message_send` - use sendbox mode if no actual messages should be send (useful for testing).

```
config :botlead, Botlead.Bot.Adapter.Telegram,
  poll_delay: 600,
  poll_limit: 100
```

Or 

```
config :botlead, Botlead.Bot.Adapter.Telegram,
  use_webhook: "https://mysite.com/TELEGRAM_SECURE_URL"
```

### Telegex

We use Telegex as adapter library for communication with Telegram platform. 

```
config :telegex,
  token: {:system, "TELEGRAM_BOT_TOKEN"}
  hook_adapter: Bandit // or Cowboy, needed for webhook mode
```

Also add server port for webhook webserver and bot name for sending updates:

```
config :botlead, Botlead.Bot.Adapter.Telegram,
  webhook: {MyApp.Bot, URL, 4000}
```

### GenRouter

Add default routing module.

```
config :gen_router, GenRouter.Conn,
  default_router: MyApp.Router
```

## Usage

Define your own `Bot`, `Client` and `Router`, plus the related controllers to process
messages recieved from bot.

### Bot

Use `Botlead.Bot.Server` and implement methods, defined by `Botlead.Bot.Behaviour`.

#### adapter_module

Return default `Botlead.Bot.Adapter.Telegram` or implement your custom adapter to connect
with your chat platform

#### client_module

Return name of your client module, which will be used to start client sessions for this bot

#### is_registered?(chat_id)

Boolean check if user was registered for the provided `chat_id`. Most likely you need to make
a database request here and query for existing user.

#### process_message_from_the_new_user(chat_id, message)

Callback for the cases then you get `message` from a new user, which is not registered in your
system. You can put soft user registration on this step and query for additional data on the
next step if it's needed

#### callback(state, callback_msg)

Optional callback, not required by protocol.

It's possible to subscribe to result of specific operations performed by bot with this method.

Current callback messages:

  * `{:before_start}` - executes just before the bot process is initialized;
  * `{:restarted_client, chat_id, new_pid}` - client session process was restarted;
  * `{:attached_client, chat_id, pid}` - client session process started;
  * `{:detached_client, chat_id}` - client session process stopped;
  * `{:processed_updates, new_updates}` - updates from chat platfrom were parsed relayed to clients.

#### Example

```
defmodule App.MyBot do
  use Botlead.Bot.Server

  @impl true
  def adapter_module, do: Botlead.Bot.Adapter.Telegram

  @impl true
  def client_module, do: App.MyClient

  @impl true
  def is_registered?(chat_id) do
    App.Repo.get_by(Account, %{telegram_chat_id: chat_id}) !== nil
  end

  @impl true
  def process_message_from_the_new_user(chat_id, _message) do
    App.Repo.insert(%Account{telegram_chat_id: chat_id})
  end

  @doc """
  Send message to a special listener pid if it's defined.
  """
  def callback(%{listener: listener_pid}, msg) when is_pid(listener_pid) do
    Process.send(listener_pid, msg, [])
    :ok
  end
  def callback(_, _), do: :ok

  @doc """
  Set listener for the bot actions.
  """
  def handle_cast({:set_listener, callback_pid}, state) when is_pid(callback_pid) do
    {:noreply, %{state | listener: callback_pid}}
  end

  @doc """
  Get all bot clients.
  """
  def handle_info({:get_clients, callback_pid}, %{clients: clients} = state) when is_pid(callback_pid) do
    Process.send(callback_pid, {:get_clients, clients}, [])
    {:noreply, state}
  end
end
```

### Client

Use `Botlead.Client.Server` and implement methods, defined by `Botlead.Client.Behaviour`.

#### router

Return name of your router module, which will be used to route bot messages

#### instance(chat_id)

Return atom with unique name for this client process

#### get_initial_state(chat_id, opts)

Return `{:ok, state}` with initial state for the client process.
Required keys: `chat_id`, `conn`, `path`, `scope`.

#### message_to_conn(message, state, opts)

Convert bot message into connection object, use your router here. Return conn object.

#### message_delivered(action, message, state)

Callback for message deliverance confirmation, returns state.

#### callback(state, callback_msg)

Optional callback, not required by protocol.

It's possible to subscribe to result of specific operations performed by bot with this method.

Current callback messages:

  * `{:parsed_message, conn}` - client message from bot was convered to conn object;
  * `{:message_delivered, action, message}` - message update was delivered to the chat platform;
  * `{:client_terminated, reason}` - client session process crashed;
  * `{:client_started, chat_id, opts}` - client session process was started.

#### Example

```
defmodule App.Client do
  use Botlead.Client.Server

  @impl true
  def router, do: App.Router

  @impl true
  def instance(chat_id), do: String.to_atom("client_#{chat_id}")

  @impl true
  def get_initial_state(chat_id, opts) do
    state = %{
      chat_id: chat_id,
      user: get_user_by_chat_id(chat_id),
      listener: Keyword.get(opts, :listener),
      conn: nil,
      path: nil,
      scope: nil
    }
    {:ok, state}
  end

  @impl true
  def message_to_conn(message, state, opts) do
    case router().match_message(message, state.path, state.scope, opts) do
      %{code: 200} = conn ->
        conn
      conn ->
        Logger.warning fn -> "Client ingores message #{inspect(message)}}" end
        conn
    end
  end

  @impl true
  def message_delivered(_action, _message, state) do
    state
  end

  def get_user_by_chat_id(chat_id) do
    App.Repo.get_by(Account, %{telegram_chat_id: chat_id})
  end

  @doc """
  Send message to a special listener pid if it's defined.
  """
  def callback(%{listener: listener_pid}, msg) when is_pid(listener_pid) do
    Process.send(listener_pid, msg, [])
    :ok
  end
  def callback(_, _), do: :ok
end
```

### Router

Check [GenRouter](https://hexdocs.pm/gen_router) docs of how to define your router and related modules.

## Other

`/restart` command in chatbot automatically restarts client session process.

**This library is in early beta, use at your own risk. Pull requests / suggestions / issues are welcome.**
