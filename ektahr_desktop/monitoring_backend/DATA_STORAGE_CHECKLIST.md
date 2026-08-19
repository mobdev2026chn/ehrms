# Why is no data appearing in MongoDB collections?

Data flows:
- **Default (no Redis):** Desktop Agent → API (processes inline, writes to MongoDB). No Redis or Worker.
- **With Redis:** Set `USE_REDIS=true` → API enqueues to Redis → Worker processes and writes.

## 1. Default: No Redis (nothing extra to install)

Do **not** set `USE_REDIS` in `.env` (or set it to `false`). Run only the API:

- `npm run start`

The API will decrypt and write to **monitoringlogs**, **monitoringscores**, **monitoringscreenshots** itself. No Redis or Worker needed.

## 2. Optional: Running with Redis

Set in `.env`: `USE_REDIS=true`

| Step | Command | What it does |
|------|---------|--------------|
| API | `npm run start` | Receives uploads, pushes to Redis queue |
| Worker | `npm run worker` | Pops from queue, decrypts, writes to MongoDB |
| Agent | `dotnet run` | Sends activity every 60s, screenshots every N minutes |

Redis must be running (e.g. Docker: `docker run -d -p 6379:6379 redis:alpine`). Also run the Worker: `npm run worker`.

## 3. RSA key (optional but recommended for production)

- The agent encrypts payloads with AES; the AES key is either RSA-wrapped (when the server sends a public key) or sent as raw base64 (when no key is set).
- **If `RSA_PRIVATE_KEY` is not set:** the Worker uses a **raw-key fallback**: it treats the job’s `encryptedKey` as the base64-encoded AES key (32 bytes). So activity/screenshots can still be stored when the server never sent a public key to the agent. For production, set RSA for better security.
- **To generate a key:** run `npm run generate-rsa` in `monitoring_backend`, then add the printed `RSA_PRIVATE_KEY=...` line to `.env`. Restart API and Worker.

## 4. Debug endpoint

With the API running, open:

- **http://localhost:9002/api/debug**

You’ll see:

- **queue.waiting** – jobs not yet processed (should go down when Worker runs).
- **queue.failed** – jobs that failed (e.g. decrypt error if RSA is missing).
- **rsaSet** – whether `RSA_PRIVATE_KEY` is set (if false, Worker still works via raw-key fallback when agent sent raw key).

## 5. When data is written

- **monitoringlogs** and **monitoringscores**: about every **60 seconds** per active agent (after the first minute).
- **monitoringscreenshots**: every **N minutes** (e.g. 5) per agent; also requires Cloudinary configured in `.env`.

## 6. Worker logs

When the Worker processes a job successfully you should see:

- `[Worker] monitoringlogs INSERT OK` (for activity)
- `[Worker] Screenshot saved` (for monitoringscreenshots)

If you see `[Worker] Job X failed: ...` (e.g. decrypt error), ensure the job’s encrypted key format matches: either RSA is set and the agent used the server’s public key, or RSA is unset and the agent sent the raw AES key. Restart Worker after changing `.env`.

## Summary checklist

**No Redis (default – nothing extra to install):**
- [ ] Do not set `USE_REDIS` in `.env`
- [ ] API is running (`npm run start`) — Worker not needed
- [ ] Desktop agent is running and has registered

**With Redis (optional):**
- [ ] `USE_REDIS=true` in `.env`
- [ ] Redis is running
- [ ] API and Worker are running
- [ ] Desktop agent is running and has registered

**Both:** `RSA_PRIVATE_KEY` in `.env` is optional (raw-key fallback works). Wait 1–2 minutes for first activity; 5+ minutes for first screenshot.

Collections: **monitoringdevices**, **monitoringlogs**, **monitoringscores**, **monitoringscreenshots**, **monitoringsettings**.
