#!/usr/bin/env bash
# Entrypoint for the FTB Skies 2: Aero server.
# Installs/updates the modpack in /data, applies server.properties, EULA and
# ops from the environment variables and starts the server.
set -euo pipefail

DATA_DIR=/data
VERSION_MARKER="$DATA_DIR/.ftb-installed-version"

log() { echo "[entrypoint] $*" >&2; }

# Started as root: hand /data over to the Unraid user (default nobody:users = 99:100)
# and restart the script without root privileges.
if [[ "$(id -u)" == "0" && "$PUID" != "0" ]]; then
  chown -R "$PUID:$PGID" "$DATA_DIR"
  exec setpriv --reuid="$PUID" --regid="$PGID" --clear-groups env HOME=/tmp "$0" "$@"
fi

cd "$DATA_DIR"

if [[ "${EULA,,}" != "true" ]]; then
  log "The Minecraft EULA has not been accepted: https://account.mojang.com/documents/minecraft_eula"
  log "Set EULA=true to start the server."
  exit 1
fi

# --- Install the modpack or change its version --------------------------------
# Empty FTB_VERSION_ID: install the newest release on the first start and keep it
# afterwards. Otherwise FTB_VERSION_ID is a version ID (e.g. 100527) or a version
# (e.g. 1.13.0) that is installed when it differs from the installed one.

# Prints "<id> <name>" of the requested version, or of the newest release if $1 is empty
resolve_version() {
  local wanted="$1" json
  if ! json="$(curl -fsS --max-time 30 "https://api.feed-the-beast.com/v1/modpacks/public/modpack/$FTB_PACK_ID")"; then
    log "WARNING: The FTB API could not be reached."
    return 1
  fi
  if ! jq -er --arg w "$wanted" '
      (if $w == "" then [.versions[] | select(.type == "release")] | max_by(.id)
       else first(.versions[] | select((.id | tostring) == $w or .name == $w)) end)
      | select(. != null) | "\(.id) \(.name)"' <<< "$json"; then
    log "WARNING: Modpack version '$wanted' does not exist, see https://www.feed-the-beast.com/modpacks/134-ftb-skies-2-aero/versions"
    return 1
  fi
}

installed_version="$(cat "$VERSION_MARKER" 2>/dev/null || true)"
requested_version="${FTB_VERSION_ID:-}"
requested_version="${requested_version//[[:space:]]/}"

if [[ -n "$installed_version" && -z "$requested_version" ]]; then
  log "Modpack version ID $installed_version is installed. Set FTB_VERSION_ID to change it."
elif [[ -n "$installed_version" && "$requested_version" == "$installed_version" ]]; then
  log "Modpack version ID $installed_version is installed."
elif target="$(resolve_version "$requested_version")"; then
  target_id="${target%% *}"
  target_name="${target#* }"
  if [[ "$target_id" == "$installed_version" ]]; then
    log "Modpack $target_name (version ID $target_id) is installed."
  else
    log "Installing FTB Skies 2: Aero $target_name (version ID $target_id, previously: ${installed_version:-none}) ..."
    ftb-serverinstall -pack "$FTB_PACK_ID" -version "$target_id" -dir "$DATA_DIR" \
      -auto -force -no-java -no-colours
    echo "$target_id" > "$VERSION_MARKER"
    log "Installation complete."
  fi
elif [[ -n "$installed_version" ]]; then
  log "Keeping the installed modpack version ID $installed_version."
else
  log "ERROR: The modpack cannot be installed without a valid version."
  exit 1
fi

# --- server.properties ----------------------------------------------------------
# On the first start, use the modpack's defaults (including allow-flight=true)
if [[ ! -f server.properties && -f default-server.properties ]]; then
  cp default-server.properties server.properties
fi
touch server.properties

set_property() {
  local tmp
  tmp="$(mktemp)"
  # Pass the values via ENVIRON so awk does not interpret backslashes (e.g. §)
  KEY="$1" VALUE="$2" awk '
    index($0, ENVIRON["KEY"] "=") == 1 { print ENVIRON["KEY"] "=" ENVIRON["VALUE"]; found = 1; next }
    { print }
    END { if (!found) print ENVIRON["KEY"] "=" ENVIRON["VALUE"] }
  ' server.properties > "$tmp"
  cat "$tmp" > server.properties
  rm -f "$tmp"
}

# Inside the container the server always listens on 25565; the host port is mapped in Unraid
set_property server-port 25565
[[ -n "$MOTD" ]] && set_property motd "$MOTD"
[[ -n "$LEVEL" ]] && set_property level-name "$LEVEL"

echo "eula=true" > eula.txt

# --- Ops ------------------------------------------------------------------------
# New names from OPS are resolved to UUIDs via the Mojang API and added to
# ops.json. Existing entries are kept.
add_op() {
  local name="$1" profile uuid
  if jq -e --arg n "$name" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' ops.json > /dev/null; then
    return 0
  fi
  if ! profile="$(curl -fsS --max-time 15 "https://api.mojang.com/users/profiles/minecraft/$name")" \
      || ! uuid="$(jq -er '.id' <<< "$profile")"; then
    log "WARNING: Player '$name' could not be resolved and is skipped."
    return 0
  fi
  uuid="$(sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12})$/\1-\2-\3-\4-\5/' <<< "$uuid")"
  name="$(jq -r '.name' <<< "$profile")"
  jq --arg u "$uuid" --arg n "$name" \
    '. + [{uuid: $u, name: $n, level: 4, bypassesPlayerLimit: false}]' ops.json > ops.json.tmp
  mv ops.json.tmp ops.json
  log "Added op: $name ($uuid)"
}

if [[ -n "${OPS//[[:space:],]/}" ]]; then
  [[ -s ops.json ]] || echo '[]' > ops.json
  IFS=',' read -ra op_names <<< "$OPS"
  for op_name in "${op_names[@]}"; do
    op_name="${op_name//[[:space:]]/}"
    [[ -z "$op_name" ]] && continue
    if [[ ! "$op_name" =~ ^[A-Za-z0-9_]{1,16}$ ]]; then
      log "WARNING: '$op_name' is not a valid Minecraft name and is skipped."
      continue
    fi
    add_op "$op_name"
  done
fi

# --- Start the server -------------------------------------------------------------
# After updates, libraries/ contains several NeoForge versions. The right one is
# referenced in the run.sh that the FTB installer writes for the installed pack version.
args_file="$(grep -oE 'libraries/net/neoforged/neoforge/[^/[:space:]]+/unix_args\.txt' run.sh 2>/dev/null | head -n 1 || true)"
if [[ ! -f "$args_file" ]]; then
  args_file="$(ls -1 libraries/net/neoforged/neoforge/*/unix_args.txt 2>/dev/null | sort -V | tail -n 1 || true)"
fi
if [[ -z "$args_file" ]]; then
  log "ERROR: NeoForge was not found in $DATA_DIR/libraries. Incomplete installation?"
  log "Delete $VERSION_MARKER to repeat the installation on the next start."
  exit 1
fi

log "Starting server: java $JVM_OPTS @$args_file nogui"
# JVM_OPTS is intentionally unquoted so it splits into separate arguments
# shellcheck disable=SC2086
exec java $JVM_OPTS "@$args_file" nogui
