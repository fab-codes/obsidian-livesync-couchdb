# obsidian-livesync-couchdb

Apache CouchDB, already configured for [Obsidian Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync):
CORS for the Obsidian clients, no anonymous access, the document size limit raised for the first
sync of a vault. One `Dockerfile`, one `.ini` file and a twenty-line entrypoint — it runs on
Railway, or on anything that can read a Dockerfile.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template?template=https%3A%2F%2Fgithub.com%2Ffab-codes%2Fobsidian-livesync-couchdb)

![CouchDB 3.5.2.1](https://img.shields.io/badge/CouchDB-3.5.2.1-e42528?logo=apachecouchdb&logoColor=white)
![Docker](https://img.shields.io/badge/image-pinned%20by%20digest-2496ed?logo=docker&logoColor=white)
![Obsidian LiveSync](https://img.shields.io/badge/Obsidian-Self--hosted%20LiveSync-7c3aed?logo=obsidian&logoColor=white)
![License MIT](https://img.shields.io/badge/license-MIT-blue)

> The button points at this repo on GitHub: if you fork or rename it, update the link URL.
> Even when starting from the button, the **volume** (step 3) has to be added by hand before
> you sync anything.

---

## What is in here

```
Dockerfile               official CouchDB image pinned by digest + the two files below
couchdb/10-livesync.ini  configuration: CORS, mandatory auth, size limits
entrypoint.sh            injects $PORT into the config, then hands over to the official entrypoint
railway.json             build from Dockerfile, healthcheck on /_up, 1 replica
docker-compose.yml       for trying it locally
scripts/smoke-test.sh    checks that an instance is configured correctly
```

---

## Deploying on Railway

### 1. Create the service

Use the button above, or: Railway → **New Project** → **Deploy from GitHub repo**.
Railway finds the `Dockerfile` on its own and reads `railway.json`.

### 2. Variables

| Variable | Value |
|---|---|
| `COUCHDB_USER` | the admin user name, e.g. `obsidian` |
| `COUCHDB_PASSWORD` | a long random password — `openssl rand -base64 36` |
| `COUCHDB_SECRET` | `openssl rand -hex 32` |

Do **not** add `PORT` on Railway. Railway injects it automatically (often as `8080`), and the
entrypoint configures CouchDB to listen on that value. The `5984` fallback is for environments
that do not provide `PORT`, such as the local Docker Compose setup below.

On Windows, to generate a secret: `[Convert]::ToBase64String((1..27 | % { Get-Random -Max 256 }))`

### 3. Volume (mandatory, before writing any data)

**Settings** → **Volumes** → **Add Volume**, mount path exactly:

```
/opt/couchdb/data
```

Without a volume every deploy starts from an empty database, and any data written before the
mount disappears the moment you mount it. Mount **only** this directory: mounting
`/opt/couchdb/etc/local.d` as well would cover up the configuration, and the server would come
back up without CORS.

### 4. Public domain

After the first deployment, go to **Settings** → **Networking** → **Generate Domain**. Railway
normally detects the listening port automatically. If it asks for a target port, use the port
shown in the deploy log (`CouchDB listening on 0.0.0.0:<port>`), commonly `8080` — do not assume
it is CouchDB's local default of `5984`. You get a `https://something.up.railway.app` with TLS
already sorted; do not append the internal port to this public URL.

### 5. Verify

```bash
./scripts/smoke-test.sh https://something.up.railway.app USER PASSWORD
```

Everything must pass. Write down the node name it prints (`nonode@nohost`): if it ever changes,
the existing databases become unreadable.

> **Cost:** a service with a volume stays up permanently, it does not scale to zero. Equivalent
> alternatives: Fly.io (officially documented by LiveSync) or a VPS with a reverse proxy in front.

---

## Trying it locally

```bash
cp .env.example .env    # and change the passwords
docker compose up --build
curl -u obsidian:YOUR_PASSWORD http://localhost:5984/_up
```

---

## Configuring Obsidian

Recent plugin versions replaced the old settings panes with an onboarding wizard, so there is no
"Remote Database configuration" screen to fill in any more.

1. Install and enable **Self-hosted LiveSync** from the community list.
2. Click the **Welcome to Self-hosted LiveSync** notice. If you already dismissed it:
   **Settings → Self-hosted LiveSync → Quick Setup → `Rerun Onboarding Wizard`**.
3. `I am setting this up for the first time` → confirm.
4. **Connection Method** → `Configure a remote manually` → `Proceed with manual configuration`.
5. **End-to-End Encryption** → turn it on here (see below); also enable `Obfuscate Properties`.
6. **Choose a synchronisation remote** → `CouchDB` → `Continue to CouchDB setup`.
7. Fill in:
   - **Server URI**: `https://something.up.railway.app` — Obsidian Mobile refuses plain HTTP,
     so `http://localhost:5984` only works for a desktop test.
   - **Username** / **Password**: the ones from `COUCHDB_USER` / `COUCHDB_PASSWORD`
   - **Database Name**: whatever you like, e.g. `obsidian-notes`. One database per vault —
     two vaults cannot share one. Lower case, starting with a letter.
   - **Use Internal API**: leave it **off**. It routes requests through Obsidian's own API to
     work around CORS, sending the credentials through one more channel. If sync works with it
     off, the CORS configuration in this repo is doing its job; turning it on hides the answer.
8. `Check server requirements` (optional, read-only) verifies the settings this repo ships.
9. `Create or connect to database and continue` — this creates the database.
10. `Restart and Initialise Server` → `I Understand, Overwrite Server`. This overwrites the
    *remote*, which is empty; local notes are untouched.
11. `No Synchronisation Settings Found` is expected on a new database → `Use this device's settings`.
12. Acknowledge that optional features stay off, and let it finish.

Then check **Sync Settings → Sync Mode**. `On Events` only syncs when one of the event toggles
below it fires, so with all of them off nothing is ever uploaded and no error is shown.
**LiveSync** is continuous and is the mode to use with CouchDB.

Once the first device works, run **`Copy settings as a new Setup URI`** from the command palette
and use that URI on every other device, instead of re-entering settings that have to match exactly.

### End-to-end encryption

The server sees your documents in the clear unless you turn on encryption in the plugin.
Before syncing anything:

- **End-to-End Encryption**: on, with a long passphrase, different from the CouchDB password.
- **Obfuscate Properties** (formerly "Path Obfuscation"): on, so that not even the file names
  end up on the server.

What an admin with full database access actually sees, with both on:

```
_id       f:5aa6a6bcb7bb57...          hashed, not a file name
path      /\:%=jnZY2xXvDXnaTcp5WdX...  ciphertext
data      %=MeMqlrb/ll+PZ+0bvENfCU...  ciphertext
e_        true                         encrypted flag
size      0      mtime  0      ctime  0
```

Three caveats:

- The passphrase is **not recoverable**: lose it and the remote database has to be rebuilt from
  scratch (your local files stay).
- Per-document metadata is zeroed, but **aggregates still leak**: how many documents exist, how
  large the database is, and when it changes are all visible to whoever runs the server.
- Turn it on **before** the first sync. Changing it later requires `Rebuild everything` and a
  re-sync of every device.

---

## Backups

The Obsidian vault on your disk **is** the primary backup: the remote database is a transport
channel between devices, not the authoritative archive. If the remote gets corrupted, throw it
away and rebuild it from a healthy client.

If you want a copy of the remote anyway (this works with encrypted documents too — you are
saving the blobs as they are):

```bash
curl -u USER:PASSWORD \
  "https://something.up.railway.app/obsidian-notes/_all_docs?include_docs=true&attachments=true" \
  -o backup-$(date +%F).json
```

---

## Updating the image

The `FROM` is pinned by digest, so it does not update on its own. To move to a newer version,
change **the tag and the digest together** in the `Dockerfile` and commit: Railway rebuilds.
Try it locally first with `docker compose up --build`.

CouchDB 3.x upgrades the data format in place, so patch and minor releases are frictionless.
Never downgrade with a populated volume.

---

## Things not to do

- **Do not set `NODENAME`.** The node name is written inside the shard maps: if it changes,
  CouchDB looks for shards on a node that no longer exists. The entrypoint warns you if it
  finds it set.
- **Do not mount volumes on `/opt/couchdb/etc/local.d`**: that would cover up the configuration.
- **Do not raise the replica count.** A Railway volume attaches to a single instance, and this
  is not a cluster.

---

## If something goes wrong

| Symptom | Almost certain cause |
|---|---|
| Deploy stuck "unhealthy" or the public URL returns `502` while the logs look fine | The domain's Target Port does not match the port in `CouchDB listening on 0.0.0.0:<port>`. Edit the domain under **Settings → Networking** and select that port. |
| `401` on everything, even with the right credentials | Admin never created: `COUCHDB_USER`/`COUCHDB_PASSWORD` missing on the first boot (look for "Admin Party" in the logs). |
| Obsidian: CORS error | A volume mounted over `local.d`, or a proxy in front rewriting the headers. |
| The database is empty after a redeploy | Volume not mounted, or mounted on a path other than `/opt/couchdb/data`. |
| `internal_server_error` on existing databases | The node name changed: compare `GET /_membership` with the one you wrote down. |
| The first sync of a large vault fails halfway | Raise `max_document_size` in `couchdb/10-livesync.ini`, or lower the chunk size in the plugin. `max_http_request_size` is already at CouchDB's own default of 4 GB. |
| Notes never reach the server, and no error is shown | **Sync Mode** is `On Events` with every event toggle off — nothing triggers a sync. Set it to `LiveSync`. If it still does not move, check `Suspend file watching` and `Suspend database reflecting` under **Hatch**: cancelling a dialogue during onboarding turns them on. |
| The Sync settings pane asks you to sign up | That is Obsidian's own paid Sync service, not this. Pick the entry labelled **Sync Settings — Self-hosted LiveSync**, and leave Obsidian Sync off: two services writing to one vault will fight. |

Full logs: the **Deployments** tab on Railway, or `docker compose logs -f` locally.

---

## License

MIT — see [LICENSE](LICENSE). Use it, change it, ship it, sell it; just keep the copyright
notice. The base image is Apache CouchDB, under the Apache License 2.0.

---

Made by [Fabrizio Greco](https://fabgreco.dev).
