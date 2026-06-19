# Campfire Bots — adding agents (Sebastian, Percy, …) to channels

How to put a conversational agent into Campfire so the team @mentions it in a
channel (or DMs it) and it replies — replacing the Slack/Discord interface.

Nothing here is new infrastructure: Campfire's bot system is built in. A bot is
just a `User` with `role: :bot`, a generated `bot_token`, and an optional
`webhook`. This doc is the contract + the steps.

---

## The two directions

```
                 (1) @mention / DM                     (3) POST reply
   Team in  ───────────────────────►  Campfire  ──────webhook──────►  Agent runtime
   Campfire                            (this app)                      (OpenClaw / Hermes / n8n)
       ▲                                                                     │
       └──────────────────  (4) reply appears as the bot  ◄─────────────────┘
                              POST /rooms/:id/:bot_key/messages
```

1. A teammate @mentions the bot in a channel, or sends it a DM.
2. Campfire fires a webhook **only** to bots that are (a) members of the room and
   (b) actually @mentioned — except in a DM, where the bot always receives it.
3. Campfire POSTs the message JSON to the bot's webhook URL (the agent runtime).
4. The agent replies (see "Replying" — sync or async). The reply shows up in the
   channel as the bot.

A bot that only *posts* (notifications/feeds, like **Athena**) needs no webhook —
it just POSTs to the room with its bot key. A bot that *responds* needs a webhook.

---

## Inbound webhook payload (Campfire → agent)

`POST <bot.webhook_url>`  ·  `Content-Type: application/json`  ·  timeout **7s**

```json
{
  "user":    { "id": 12, "name": "Don Ho" },
  "room":    { "id": 2, "name": "war-room",
               "path": "/rooms/2/2-AbC123dEf456/messages" },
  "message": { "id": 4567,
               "body": { "html": "<div>…@Sebastian what's our P0?…</div>",
                         "plain": "what's our P0?" },
               "path": "/rooms/2/@4567" }
}
```

- `room.path` is the **reply URL with the bot key already in it** — POST your
  answer there. (Prefix with the Campfire host: `https://campfire.kaizenailab.com`.)
- `message.body.plain` has the bot's own @mention stripped — feed this to the model.
- `user.name` is who asked.

## Replying

**Option A — synchronous (only for instant replies <7s).** Return the reply as
the HTTP response body with `Content-Type: text/plain` (or `text/html`) and
status 200. Campfire posts that body as the bot's message automatically. If you
exceed 7s, Campfire posts "Failed to respond within 7 seconds."

**Option B — asynchronous (use this for LLM agents).** Respond **204 / empty**
immediately (so Campfire posts nothing), then when the model finishes, POST the
answer yourself:

```
POST https://campfire.kaizenailab.com{room.path}
Content-Type: text/plain

<the agent's answer>
```

That's it — no key management needed, the key is inside `room.path`. For
*proactive* posts (the agent speaking unprompted, like Athena), use the bot's own
key: `POST /rooms/:room_id/<bot_key>/messages`.

---

## Reference receiver (async) — adapt per runtime

Language-neutral; this is the adapter that replaces each agent's Slack/Discord
connector. Point the bot's webhook URL at this endpoint.

```js
// Express example. Sebastian (OpenClaw) / an n8n Function node / Hermes handler
// all follow the same shape.
const CAMPFIRE = "https://campfire.kaizenailab.com";

app.post("/campfire/sebastian", express.json(), (req, res) => {
  const { user, room, message } = req.body;
  res.status(204).end();                       // 1. ack immediately (<7s)

  runAgent({                                   // 2. existing agent logic
    prompt: message.body.plain,
    from: user.name,
    room: room.name,
  }).then(answer => {
    fetch(CAMPFIRE + room.path, {              // 3. post the reply via room.path
      method: "POST",
      headers: { "Content-Type": "text/plain" },
      body: answer,
    });
  });
});
```

Notes:
- **Verify the caller.** The webhook is unauthenticated by default. Put the
  endpoint on an unguessable path and/or check a shared secret in a header you
  add, or allowlist Campfire's egress. Treat the payload as untrusted input.
- **Long jobs:** ack 204, do the work, post when ready. You can post multiple
  times (e.g. "working on it…" then the result).

---

## Step-by-step: add a bot

1. **Create the bot.** In Campfire, open **Settings** (gear) → **Chat bots** →
   **Add a chat bot**. Set the name (e.g. `Sebastian 🦀`), an avatar, and the
   **webhook URL** (the agent endpoint above). Save. Campfire shows the bot's
   **key** (`<id>-<token>`) — copy it if the agent will post proactively;
   reply-only bots don't need it (they use `room.path`).
2. **Add the bot to channels.** Open each channel the team will talk to it in and
   add the bot as a member (it must be a member to be @mentionable and to receive
   room webhooks). For DMs, just start a DM with it.
3. **Wire the agent.** Implement the receiver (reference above) in the agent's
   runtime so it acks fast and posts back via `room.path`. (Hermes/Percy is Don's
   trial — wire it there yourself; I can help with the OpenClaw/n8n side.)
4. **Test.** In a channel the bot is in, type `@Sebastian ping`. Within a second
   Campfire delivers the webhook; the agent's reply appears as the bot.

## Rotating / editing
- Edit name/avatar/webhook anytime in **Settings → Chat bots → (bot) → Edit**.
- Reset a leaked key from the same edit screen (old key stops working immediately).

## Optional: repeatable provisioning
If you want the bot roster re-created automatically after a DB reset (instead of
clicking through the UI), say so and we'll add a small `campfire:bots:provision`
rake task driven by a checked-in `config/bots.yml` (names + webhook URLs from
env). Not required — bots created in the UI persist on the Railway volume.
