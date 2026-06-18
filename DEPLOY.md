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
5. Check **Deployments → Logs**: you should see
   `[server] listening on port <PORT> — waiting for two players`.

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

## Part 3 — Export the web client & publish on itch.io

8. In Godot: **Editor → Manage Export Templates → Download and Install** (once).
9. **Project → Export → Add… → Web**. Leave defaults; set **Export Path** to
   `build/web/index.html`. (Create the `build/web` folder if needed.)
10. Click **Export Project** (untick "Export With Debug"). This writes
    `index.html`, `index.wasm`, `index.pck`, `index.js`, etc. into `build/web/`.
11. Zip the **contents** of `build/web/` (so `index.html` is at the zip root) —
    e.g. `web-build.zip`.
12. Go to <https://itch.io>, sign up, **Dashboard → Create new project**:
    - **Kind of project:** HTML
    - **Upload** `web-build.zip` and tick **"This file will be played in the
      browser."**
    - **Embed options:** set a size (e.g. 1280×720) and enable
      **"SharedArrayBuffer support"** (required for Godot 4 web).
    - Set visibility to Draft/Public, **Save**.
13. Open the project page → **Run game**. Share the link with a friend: both open
    it, click **MULTIPLAYER → CONNECT** (URL is pre-filled with your server) →
    pick **Human**/**Zombie** → play.

---

## Notes / gotchas

- **Idle disconnects:** Railway drops idle WebSocket connections after ~15 min.
  Auto-reconnect is Phase D (not built yet) — fine for normal play sessions.
- **Native download instead of web:** export a Windows/macOS/Linux build instead
  of Web; it talks to the same Railway server and needs no special host (itch.io
  optional). No header/SharedArrayBuffer concerns for native.
- **Version match:** the Railway `GODOT_VERSION` and your editor version must
  match the project, or imports/exports can misbehave.
