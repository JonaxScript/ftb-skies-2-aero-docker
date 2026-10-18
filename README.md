# FTB Skies 2: Aero – Docker server for Unraid

Docker image and Unraid template for a dedicated server running the
[FTB Skies 2: Aero](https://www.feed-the-beast.com/modpacks/134-ftb-skies-2-aero) modpack
(Minecraft 1.21.1, NeoForge 21.1.250, Java 21).

The image contains Java 21 and the official FTB server installer. On the **first start** the
modpack (about 1.3 GB) is installed into `/data`; after that the server starts right away.

| File | Purpose |
|---|---|
| `Dockerfile` | Image definition |
| `entrypoint.sh` | Install/update, `server.properties`, EULA, ops, server start |
| `unraid/ftb-skies-2-aero.xml` | Unraid template with all variables |
| `docker-compose.yml` | For local testing, e.g. with Docker Desktop |

## Install on Unraid

The image is built directly on your Unraid server, so no registry account is needed.

1. **Build the image and add the template:** Open the terminal in the Unraid web UI (`>_` icon, top right) and run:

   ```sh
   REPO=https://raw.githubusercontent.com/JonaxScript/ftb-skies-2-aero-docker/main
   mkdir -p /tmp/ftb-skies-2-aero && cd /tmp/ftb-skies-2-aero
   curl -fsSL -O "$REPO/Dockerfile" -O "$REPO/entrypoint.sh"
   docker build -t ftb-skies-2-aero:latest .
   curl -fsSL --create-dirs -o /boot/config/plugins/dockerMan/templates-user/my-FTB-Skies-2-Aero.xml "$REPO/unraid/ftb-skies-2-aero.xml"
   ```

   You can ignore a "legacy builder is deprecated" warning.
2. **Create the container:** **Docker** → **Add Container** → under **Template**, pick **FTB-Skies-2-Aero**
   from *User templates*.
3. Set `EULA` to `true`, adjust `OPS`, `MOTD` and the RAM in `JVM_OPTS` → **Apply**.
4. **Watch the start:** In the Docker tab, click the container icon → **Logs**. The first install takes a few
   minutes, the first server start including world generation a few more. The server is ready when it logs
   `Done (...)! For help, type "help"`.
5. **Connect:** In the FTB App (same pack version, currently 1.13.0), add the server `<unraid-ip>:25565`.

Because the image is built locally, the update column in the Docker tab shows "not available". That is expected:
modpack updates are done via `FTB_VERSION_ID`, see [Modpack updates](#modpack-updates).

### Alternative: Docker Hub

You can also build the image on another machine and push it to [Docker Hub](https://hub.docker.com):

```sh
docker login
docker build -t YOUR-DOCKERHUB-NAME/ftb-skies-2-aero:latest .
docker push YOUR-DOCKERHUB-NAME/ftb-skies-2-aero:latest
```

On Unraid, download only the template (the last command of step 1) and set **Repository** in the container
settings to `YOUR-DOCKERHUB-NAME/ftb-skies-2-aero:latest`.

## Variables

| Variable | Default | Description |
|---|---|---|
| `EULA` | `false` | Must be `true`, otherwise the server does not start ([Minecraft EULA](https://account.mojang.com/documents/minecraft_eula)) |
| `JVM_OPTS` | `-Xms6G -Xmx8G` | Java options (FTB recommends 8 GB RAM, minimum 6 GB) |
| `OPS` | empty | Comma-separated player names, e.g. `Player1,Player2`. They are resolved to UUIDs via the Mojang API on start and added to `ops.json`. Remove ops in-game with `/deop`. |
| `MOTD` | `FTB Skies 2: Aero` | Message shown in the server list (colour codes as `§b` etc.) |
| `LEVEL` | `world` | Name of the world directory |
| Port `25565/tcp` | `25565` | Game port; the host port can be anything in Unraid |
| `PUID` / `PGID` | `99` / `100` | Owner of the files in `/data` (Unraid default `nobody:users`) |
| `FTB_VERSION_ID` | `100527` (1.13.0) | Modpack version, see [Modpack updates](#modpack-updates) |

Path: `/data` → `/mnt/user/appdata/ftb-skies-2-aero` (world, configs, mods, logs).
In Unraid, `LEVEL`, the path, `PUID`/`PGID` and `FTB_VERSION_ID` are under *Show more settings*.

## Modpack updates

Updates are not automatic; the version is pinned via `FTB_VERSION_ID`. To update:

1. Find the new version ID: the [FTB versions page](https://www.feed-the-beast.com/modpacks/134-ftb-skies-2-aero/versions)
   lists it for every version, e.g. "1.13.0 Release ID 100527".
2. Stop the container and back up the appdata folder, at least the world folder
   (e.g. with the *Appdata Backup* plugin from Community Apps).
3. In Unraid, edit the container → *Show more settings* → change `FTB_VERSION_ID` → **Apply**.
4. All players update the pack to the same version in the FTB App.

On start, the container detects the new ID (`/data/.ftb-installed-version`) and runs the FTB installer as an update.
The image does not need to be rebuilt. Tested with an update from 1.10.0 to 1.13.0:

| Kept | Replaced or removed |
|---|---|
| World (including `world/serverconfig`) | Configs the pack changed in the new version. Your own edits to those files are lost, without a backup. |
| `server.properties`, `ops.json`, whitelist | Mods the pack updated or removed |
| Configs the pack did not change, including your edits | |
| Mods and config files you added yourself | |

**Rolling back:** Restore the backup and set `FTB_VERSION_ID` back to the old ID. Only resetting the ID also
works (the installer then downgrades), but the world has already been loaded by the newer version.

To repair a broken installation, delete `.ftb-installed-version` and restart the container.

### Updating the image

Only needed when `Dockerfile` or `entrypoint.sh` change: run the first four commands of the installation again
(not the last one for the template), then edit the container → **Apply** so it is recreated with the new image.
Do not download the template again, because Unraid stores your settings in that very file.

## Local testing

Set `EULA` to `"true"` in `docker-compose.yml`, then run:

```sh
docker compose up --build
```

The server data is stored in the Docker volume `ftb-data`.

## Notes

- `-Xmx` must fit into the free RAM of your server; Java needs roughly 1–2 GB on top of `-Xmx`.
- The template sets `--stop-timeout=120` so the server has enough time to save the world when it stops
  (otherwise Docker kills containers after 10 seconds).
- `server.properties` is created from the modpack's defaults on the first start (including `allow-flight=true`,
  which matters for airships). After that, only `motd`, `level-name` and `server-port` are set on every start;
  you can change everything else directly in the file.
- `run.sh` and `user_jvm_args.txt` from the FTB installer are not executed (`run.sh` is only read to find the
  installed NeoForge version). Memory and Java options come from `JVM_OPTS` only.
- Server console: add `-it` to *Extra Parameters* to send commands via `docker attach FTB-Skies-2-Aero`
  (detach with `Ctrl+P`, `Ctrl+Q`). Alternatively, run commands in-game as an op.
- x86-64 only (the Unraid default).
- This project is not affiliated with Feed The Beast or Mojang.
