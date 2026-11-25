# Deploying online: Railway (server) + itch.io (web client)

Order matters: deploy the **server first** to get its URL, then bake that URL
into the **client** and publish it.

---

## Part 1 — Deploy the server to Railway

1. Commit & push the repo to GitHub (it already includes `Dockerfile` and
   `.dockerignore`).
2. Go to <https://railway.app>, sign up, **New Project → Deploy from GitHub repo**,
   pick `Zombie-game`.
3. Railway detects the `Dockerfile` and builds automatically.
   - If the build can't find the Godot download, your version differs from the
     default. In the service **Variables**, add `GODOT_VERSION` = your editor's
     version, e.g. `4.6.3-stable` (see the Godot title bar).
4. Open the service → **Settings → Networking → Generate Domain**. You'll get
   something like `zombie-game-production.up.railway.app`.
5. Check **Deployments → Logs**: you should see the **director** boot, e.g.
   `[director] listening on :<PORT> — pool cap 5, children from port 8911, ...`.
   Each hosted game then spawns a child that logs `[server] listening on port
   8911 …`. Multiple matches run at once (up to `MAX_GAMES`).

➡️ Your server URL is `wss://<that-domain>` — **no port** (Railway proxies 443 to
the container). Note it: CORS / `FRONTEND_URL` is **not** needed (raw WebSocket).

---

## Part 2 — Point the client at the live server

6. Edit `scripts/network.gd` → set:
   ```gdscript
   const PROD_SERVER_URL := "wss://<your-domain>.up.railway.app"
   ```
7. Save. (Exported builds auto-use this; the editor still uses localhost.)

---

## Part 3: Tester builds (macOS and Windows)

The web build is gone. The 3D game needs the Forward+ renderer, which browsers
can't run, so testers get a native app. `export_presets.cfg` has two presets.
Export templates for 4.6.3 must be installed (Editor → Manage Export Templates).

8. **Export.** In the editor: **Project → Export → macOS** (or **Windows**) →
   **Export Project**, and untick "Export With Debug". From a terminal, with the
   editor closed:
   ```
   Godot --headless --path . --export-release "macOS" build/mac/ZombieGame.zip
   Godot --headless --path . --export-release "Windows" build/windows/ZombieGame.exe
   ```
   The Mac build is a universal (Intel and Apple Silicon) `.app` inside a zip,
   about 70 MB. The Windows build is a single `.exe`, about 115 MB. `build/` is
   gitignored.
9. **Send it.** Share the zip, or the `.exe` zipped, through any file share.
10. **First launch (the builds aren't signed):**
    - **Mac:** unzip, then **right-click "Zombie Game" → Open → Open**. If macOS
      says it "can't be opened", go to **System Settings → Privacy & Security**,
      click **Open Anyway** next to the message, then open it again.
    - **Windows:** double-click. If SmartScreen warns, click **More info → Run
      anyway**.
11. **What the tester gets:** the menu. PLAY → shooter or zombie commander →
    the small 3D city. ESC opens the in-game menu: switch role, cheats (all
    weapons + unlimited ammo), settings, restart, quit. H shows the debug
    sliders. Online play is hidden until the 3D game is networked (plan phase 5).

---

## Notes / gotchas

- **Concurrent games:** one Railway service now runs several matches at once via
  the Go **director** (`server/director/`), which pools single-match Godot
  children. It keeps a small **warm buffer** of pre-booted children so hosting is
  instant. Tunables (service **Variables**, all optional): `MAX_GAMES` (default
  5), `WARM_CHILDREN` (1), `INTERNAL_BASE_PORT` (8911). The client URL is
  unchanged — `network.gd` appends `?host`/`?join=CODE` itself. See
  `ARCHITECTURE.md` → *Server topology*.
- **Idle disconnects:** Railway drops idle WebSocket connections after ~15 min.
  Auto-reconnect is Phase D (not built yet) — fine for normal play sessions.
- **Version match:** the Railway `GODOT_VERSION` and your editor version must
  match the project, or imports/exports can misbehave.
