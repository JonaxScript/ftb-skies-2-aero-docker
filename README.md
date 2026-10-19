# FTB Skies 2: Aero – Docker server for Unraid

Docker image and Unraid template for a dedicated server running the
[FTB Skies 2: Aero](https://www.feed-the-beast.com/modpacks/134-ftb-skies-2-aero) modpack
(Minecraft 1.21.1, NeoForge, Java 21).

On Unraid, install it from the **Apps** tab (Community Apps) as **FTB-Skies-2-Aero**. The image is on Docker Hub
as [`jonaxio/ftb-skies-2-aero`](https://hub.docker.com/r/jonaxio/ftb-skies-2-aero) and contains Java 21 and the
official FTB server installer. On the **first start** the newest version of the modpack (about 1.3 GB) is
installed into `/data`; after that the server starts right away.

| File | Purpose |
|---|---|
| `Dockerfile` | Image definition |
| `entrypoint.sh` | Install/update, `server.properties`, EULA, ops, server start |
| `templates/ftb-skies-2-aero.xml` | Unraid template used by Community Apps |
| `ca_profile.xml` | Repository profile for Unraid Community Apps |
| `docker-compose.yml` | For local testing, e.g. with Docker Desktop |

## Install on Unraid

1. In the **Apps** tab, search for **FTB-Skies-2-Aero** and click **Install**.
2. Set `EULA` to `true`, adjust `OPS`, `MOTD` and the RAM in `JVM_OPTS` → **Apply**. Unraid downloads the
   image from Docker Hub and starts the container.
3. **Watch the start:** In the Docker tab, click the container icon → **Logs**. The first install takes a few
   minutes, the first server start including world generation a few more. The server is ready when it logs
   `Done (...)! For help, type "help"`.
4. **Connect:** In the FTB App (same pack version as the server, shown in the logs), add the server
   `<unraid-ip>:25565`.

### Image updates

When a new image is published, the Docker tab shows **update ready** for the container; click it and confirm
with **apply update**. The world and all server files are kept in the appdata folder, and your settings stay
in the template. Modpack updates are separate, see [Modpack updates](#modpack-updates).

## Install with Docker (without Unraid)

Setting `EULA=true` means you accept the [Minecraft EULA](https://account.mojang.com/documents/minecraft_eula).

```sh
docker run -d --name ftb-skies-2-aero --restart unless-stopped --stop-timeout 120 \
  -p 25565:25565 -v ftb-data:/data -e EULA=true jonaxio/ftb-skies-2-aero:latest
```

Or with Docker Compose (save as `compose.yaml`, then run `docker compose up -d`):

```yaml
services:
  ftb-skies-2-aero:
    image: jonaxio/ftb-skies-2-aero:latest
    container_name: ftb-skies-2-aero
    ports:
      - "25565:25565"
    environment:
      EULA: "true"
      JVM_OPTS: "-Xms6G -Xmx8G"
    volumes:
      - ftb-data:/data
    stop_grace_period: 2m
    restart: unless-stopped

volumes:
  ftb-data:
```

- Follow the start with `docker logs -f ftb-skies-2-aero`.
- All [variables](#variables) can be set with `-e` or under `environment`.
- With a bind mount (e.g. `./data:/data`) instead of a volume, set `PUID` and `PGID` to your own user
  (`id -u`, `id -g`) so the files belong to you.
- Image updates: `docker compose pull && docker compose up -d`. With `docker run`, pull the image, remove the
  container and run the command again; the data stays in the volume.

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
| `FTB_VERSION_ID` | empty | Modpack version (e.g. `1.13.0`) or version ID (e.g. `100527`). Empty: the newest version is installed on the first start and kept afterwards. See [Modpack updates](#modpack-updates). |

Path: `/data` → `/mnt/user/appdata/ftb-skies-2-aero` (world, configs, mods, logs).
In Unraid, `LEVEL`, the path, `PUID`/`PGID` and `FTB_VERSION_ID` are under *Show more settings*.

## Modpack updates

On the first start the newest modpack version is installed. After that, the installed version is kept until
you enter another one in `FTB_VERSION_ID`. To update:

1. Look up the new version on the [FTB versions page](https://www.feed-the-beast.com/modpacks/134-ftb-skies-2-aero/versions),
   e.g. "1.13.0 Release ID 100527". `FTB_VERSION_ID` accepts the version (`1.13.0`) or the ID (`100527`).
2. Stop the container and back up the appdata folder, at least the world folder
   (e.g. with the *Appdata Backup* plugin from Community Apps).
3. In Unraid, edit the container → *Show more settings* → enter the version in `FTB_VERSION_ID` → **Apply**.
4. All players update the pack to the same version in the FTB App.

On start, the container compares the entered version with the installed one (`/data/.ftb-installed-version`)
and runs the FTB installer as an update if they differ. No new image is needed for this. If the version does not
exist or the FTB API cannot be reached, the installed version keeps running. Tested with an update from 1.10.0
to 1.13.0:

| Kept | Replaced or removed |
|---|---|
| World (including `world/serverconfig`) | Configs the pack changed in the new version. Your own edits to those files are lost, without a backup. |
| `server.properties`, `ops.json`, whitelist | Mods the pack updated or removed |
| Configs the pack did not change, including your edits | |
| Mods and config files you added yourself | |

**Rolling back:** Restore the backup and enter the old version in `FTB_VERSION_ID`. Only entering the old version
also works (the installer then downgrades), but the world has already been loaded by the newer version.

To repair a broken installation, delete `.ftb-installed-version` and restart the container.

## Building the image yourself

**Local testing:** Set `EULA` to `"true"` in `docker-compose.yml`, then run `docker compose up --build`.
The server data is stored in the Docker volume `ftb-data`.

**Own build on Unraid:** Build with `docker build -t ftb-skies-2-aero:latest .` and set **Repository** in the
container settings to `ftb-skies-2-aero:latest`. The update column then shows "not available", which is expected
for local images.

**Publishing to Docker Hub** (maintainers):

```sh
docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  --output type=image,name=docker.io/jonaxio/ftb-skies-2-aero:latest,push=true,oci-mediatypes=false .
```

This pushes a plain single-platform Docker manifest without attestations, the same format a classic
`docker push` creates.

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

## License

The files in this repository are licensed under the [MIT License](LICENSE). The modpack, Minecraft and the
FTB server installer are downloaded at runtime and are subject to their own licenses and the Minecraft EULA.
This project is not affiliated with Feed The Beast or Mojang.
