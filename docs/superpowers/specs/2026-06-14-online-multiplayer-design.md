# Online Multiplayer — Headless Godot Server + Web Client

**Phase 6:** Take the existing LAN/localhost WebSocket multiplayer online so two
people on different networks can play in a browser.

## Decision (locked in)

- **Architecture:** Authoritative dedicated **headless Godot server** (the same
  GDScript game logic you already have), with two thin **web-export clients**.
  This is the "Among Us" model — a central server prevents cheating and is the
  source of truth — but reusing your Godot code instead of rewriting in Node.
- **Deploy:** Server → **Railway** (Docker, gives a public `wss://` URL).
  Client → **itch.io** (HTML5/Web export).
- **NOT** rewriting in Node/Socket.IO/Phaser. The pasted blueprint is for a
  from-scratch JS game; we already have a working Godot game.
- P2P / WebRTC is explicitly **future work** (cheaper hosting later, more complex
  now).

## What already exists (reused)

- `Net` autoload (`scripts/network.gd`): `WebSocketMultiplayerPeer`, host/join,
  role assignment, start_game, 2-player cap.
- `world.gd`: server-authoritative spawning/sim gated on `multiplayer.is_server()`.
- Main-menu lobby: Host / Join / role select / "waiting for player".

## The core change

Today the **host is also a player**. Online, the host becomes a **dedicated
server that is NOT a player** — both the Human and the Zombie connect as clients.
That's the main refactor.

---

## Plan

### Phase A — Dedicated server mode (test on localhost)
Code only; nothing deployed yet.

1. **Server launch path.** Detect `--server` in cmdline args → headless, call
   `Net.host()` reading the port from the `PORT` env var (Railway sets this;
   default `8910` locally). Server does not pick a role or spawn a local camera.
2. **Server-arbitrated lobby role pick.** Both players connect as clients and
   land in an online lobby. Each picks Human or Zombie; the **server arbitrates**
   (a role can only be claimed by one peer — second claimant is rejected and the
   lobby UI reflects the truth via a broadcast role map). When both roles are
   claimed by two distinct peers, the server starts the match, broadcasting each
   peer's role + the shared world seed via RPC.
3. **Headless guard in `world.gd`.** On the dedicated server, skip camera / HUD /
   fog setup (guard on a `GameState.is_dedicated_server` flag). Server still runs
   the full simulation; it just renders nothing.
4. **Local verification:** run `godot --headless -- --server` + two desktop
   client windows connecting to `127.0.0.1`. Confirm both roles play correctly.

### Phase B — Web client export
1. Add a **Web export preset**; export the client.
2. Make the client connect URL **configurable** (a field / build constant), so it
   can point at `ws://127.0.0.1:8910` locally and `wss://<railway-url>` in prod.
3. Verify a browser client (web export) plays against the local headless server.

### Phase C — Deploy
1. **Dockerfile** that runs the exported Linux headless server build with
   `--server`, listening on `$PORT`.
2. **Railway:** deploy from GitHub, get the public `wss://...up.railway.app` URL.
3. Point the web client at that URL, **export, and upload the zip to itch.io**
   (web-playable).
4. I'll give you a **step-by-step manual checklist** for the parts only you can
   do (create Railway project, set env vars, upload to itch.io).

### Phase D — Robustness (future, not now)
Auto-reconnect on drop, re-join by player/room id (Railway drops idle sockets),
room codes / multiple concurrent lobbies.

---

## Division of labor

- **I do (code):** server mode, role-assignment refactor, headless guards, web
  export preset, configurable connect URL, Dockerfile, deploy instructions.
- **You do (manual, with my step-by-step):** create Railway project + deploy,
  set env vars, create itch.io page + upload the web build. (You handle all
  `git push` yourself, per your standing instruction.)

## Risks / notes

- Browser pages on `https://` (itch.io) can only open `wss://`. Railway
  terminates TLS at its edge and proxies plain `ws` to the container, so the
  Godot server stays on plain ws and we don't manage certs. ✅
- Web exports usually need threads disabled; will set the preset accordingly.
- Keeping a single-room / 2-player model for now (matches existing cap). Room
  codes are Phase D.

## Success criteria

Two people on different networks open the itch.io page in their browsers, one
plays Human and one plays Zombie against the Railway-hosted authoritative server,
with the same gameplay as local multiplayer.
