#!/usr/bin/env bash
set -euo pipefail

# ---------- CONFIG ----------

# variables
CONFIG_DIR="$HOME/.pspr" # config folder
CONFIG_FILE="$CONFIG_DIR/config" # config file

# ensure_config()
# create the config folder and file if it does not exist
ensure_config() {
  mkdir -p "$CONFIG_DIR"
  [[ -f "$CONFIG_FILE" ]] || : > "$CONFIG_FILE"
}

# print_logo()
# shown by pspr usage
print_logo() {
  echo "                             "
  echo "         @@@@@@@@@@@         "
  echo "      @@@@@@@@@@@@@@@@@      "
  echo "    @@@@@@@@@@@@@@@@@@@@@    "
  echo "  @@@@@@@@@@@@@@@@@@@@@@@@@  "
  echo " @@@@@@@@@         @@@@@@@@@ "
  echo " @@@@@@@    @@@@@    @@@@@@@ "
  echo "@@@@@@@@@  @@@@@@@@@  @@@@@@@@"
  echo "@@@@@@@@   @@@@@@@@@   @@@@@@@"
  echo "@@@@@@@@   @@@@@@@@@  @@@@@@@@"
  echo " @@@@@@     @@@@@    @@@@@@@ "
  echo " @@@@@@            @@@@@@@@@ "
  echo "  @@@@@   @@@@@@@@@@@@@@@@@  "
  echo "    @@@   @@@@@@@@@@@@@@@    "
  echo "      @   @@@@@@@@@@@@@      "
  echo "          @@@@@@@@@@         "
  echo "                             "
}

# usage()
# display the usage of the CLI tool
usage() {
  cat <<'EOF'
Phosphor.social - pspr

Config:
  File: ~/.pspr/config
  Format: key: value
  Keys:
    path: base directory for projects (e.g. /Volumes/Projects)
    dmg:  absolute path to dmg file
    s3_bucket_name: S3 bucket name
    s3_endpoint: Cloudflare R2 endpoint (e.g. https://xxxx.r2.cloudflarestorage.com)
    s3_region: region (use "auto" for R2)
    s3_access_key_id: access key id
    s3_secret_access_key: secret access key
    rclone_config_name: rclone remote name (e.g. r2)

Usage:
  pspr config get <key>
  pspr config set <key> <value>
  pspr config list
  pspr config delete <key>
  pspr config reset
  pspr open
  pspr open <foldername>
  pspr open <foldername> <filename>
  pspr close
  pspr sync <foldername> # interactive output
  pspr sync --quiet <foldername> # silent output
  pspr unsync <foldername>
  pspr update
EOF
}

# validate_key()
# validate the name of a key
validate_key() {
  local key="$1"
  if [[ ! "$key" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "Invalid key: $key (allowed: letters, numbers, _)" >&2
    exit 1
  fi
}

# cmd_config_get()
# get a config key value
cmd_config_get() {
  local key="$1"
  validate_key "$key"
  ensure_config

  awk -v KEY="$key" '
    /^[[:space:]]*[^:#][^:]*:/ {
      line = $0
      c = index(line, ":")
      if (c == 0) next
      k = substr(line, 1, c - 1)
      sub(/^[[:space:]]+/, "", k)
      sub(/[[:space:]]+$/, "", k)
      if (k == KEY) {
        val = substr(line, c + 1)
        sub(/^[[:space:]]+/, "", val)
        print val
        exit 0
      }
    }
  ' "$CONFIG_FILE" || exit 1
}

# cmd_config_set()
# set a config key value
cmd_config_set() {
  local key="$1"
  local value="$2"
  validate_key "$key"
  ensure_config

  awk -v KEY="$key" -v VAL="$value" '
    BEGIN { updated = 0 }
    {
      line = $0
      c = index(line, ":")
      if (c > 0) {
        k = substr(line, 1, c - 1)
        sub(/^[[:space:]]+/, "", k)
        sub(/[[:space:]]+$/, "", k)
        if (k == KEY && updated == 0) {
          print KEY ": " VAL
          updated = 1
          next
        }
      }
      print $0
    }
    END {
      if (updated == 0) {
        print KEY ": " VAL
      }
    }
  ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

# cmd_config_list()
# print all config keys and values (sorted, skipping blank/comment lines)
cmd_config_list() {
  ensure_config
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*[^:#][^:]*:/ {
      line = $0
      c = index(line, ":")
      if (c == 0) next
      k = substr(line, 1, c - 1)
      v = substr(line, c + 1)
      sub(/^[[:space:]]+/, "", k)
      sub(/[[:space:]]+$/, "", k)
      sub(/^[[:space:]]+/, "", v)
      print k ": " v
    }
  ' "$CONFIG_FILE" | sort -f
}

# cmd_config_delete()
# delete a config key
cmd_config_delete() {
  local key="$1"
  validate_key "$key"
  ensure_config

  # Remove any line whose key (before first :) matches exactly
  awk -v KEY="$key" '
    {
      line = $0
      c = index(line, ":")
      if (c == 0) { print $0; next }
      k = substr(line, 1, c - 1)
      sub(/^[[:space:]]+/, "", k)
      sub(/[[:space:]]+$/, "", k)
      if (k == KEY) next
      print $0
    }
  ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

# cmd_config_reset()
# reset all config variables (clear the config file)
cmd_config_reset() {
  ensure_config
  : >"$CONFIG_FILE"
  echo "Config reset: $CONFIG_FILE"
}

# expand_path()
expand_path() {
  local p="$1"
  if [[ "$p" == "~"* ]]; then
    p="${p/#\~/$HOME}"
  fi
  p="${p%/}"
  print -r -- "$p"
}

# load_config_or_die()
# loads required sync config values from ~/.pspr/config or exits with error
load_config_or_die() {
  ensure_config
  local missing=()

  S3_BUCKET_NAME="$(cmd_config_get s3_bucket_name 2>/dev/null || true)"
  [[ -n "$S3_BUCKET_NAME" ]] || missing+=("s3_bucket_name")

  S3_ENDPOINT="$(cmd_config_get s3_endpoint 2>/dev/null || true)"
  [[ -n "$S3_ENDPOINT" ]] || missing+=("s3_endpoint")

  S3_REGION="$(cmd_config_get s3_region 2>/dev/null || true)"
  [[ -n "$S3_REGION" ]] || missing+=("s3_region")

  S3_ACCESS_KEY_ID="$(cmd_config_get s3_access_key_id 2>/dev/null || true)"
  [[ -n "$S3_ACCESS_KEY_ID" ]] || missing+=("s3_access_key_id")

  S3_SECRET_ACCESS_KEY="$(cmd_config_get s3_secret_access_key 2>/dev/null || true)"
  [[ -n "$S3_SECRET_ACCESS_KEY" ]] || missing+=("s3_secret_access_key")

  RCLONE_REMOTE_NAME="$(cmd_config_get rclone_config_name 2>/dev/null || true)"
  [[ -n "$RCLONE_REMOTE_NAME" ]] || missing+=("rclone_config_name")

  if (( ${#missing[@]} > 0 )); then
    echo "Missing required config key(s): ${missing[*]}" >&2
    echo "Set them with: pspr config set <key> <value>" >&2
    exit 1
  fi
}

# ensure_rclone()
# ensure rclone CLI exists
ensure_rclone() {
  if ! command -v rclone >/dev/null 2>&1; then
    echo 'rclone not found. Install it (e.g., `brew install rclone`).' >&2
    exit 1
  fi
}

# ---------- OPEN ----------

# require_editor_cli()
# always require vscode
require_editor_cli() {
  if ! command -v code >/dev/null 2>&1; then
    echo 'Visual Studio Code CLI "code" not found. Install VS Code and its CLI (e.g., `brew install --cask visual-studio-code`).' >&2
    exit 1
  fi
}

# open_with_editor()
# open the file with the editor
open_with_editor() {
  code "$@"
}

# parse_open_args()
# function to parse the open arguments
parse_open_args() {
  OPEN_MODE="mount"
  OPEN_FOLDER=""
  OPEN_FILE=""

  if (( $# == 0 )); then
    return
  fi

  OPEN_MODE="edit"
  local args=("$@")
  local i=1
  while (( i <= ${#args} )); do
    local a="${args[i]}"
    case "$a" in
      -*)
        echo "Unknown flag: $a" >&2
        exit 1
        ;;
      *)
        if [[ -z "$OPEN_FOLDER" ]]; then
          OPEN_FOLDER="$a"
        elif [[ -z "$OPEN_FILE" ]]; then
          OPEN_FILE="$a"
        else
          echo "Too many positional args. Usage: pspr open <foldername> <filename>" >&2
          exit 1
        fi
        ;;
    esac
    (( i++ ))
  done

  if [[ -z "$OPEN_FOLDER" ]]; then
    echo "Missing <foldername>. Usage: pspr open <foldername> <filename>" >&2
    exit 1
  fi
}

# is_dmg_mounted()
# check if the dmg is already mounted
is_dmg_mounted() {
  local dmg_path="$1"
  hdiutil info | grep -F "image-path" | grep -Fq -- "$dmg_path"
}

# cmd_mount_dmg()
# mount the dmg
cmd_mount_dmg() {
  local dmg_path
  if ! dmg_path="$(cmd_config_get dmg 2>/dev/null)"; then
    echo 'Missing config "dmg". Set it with: pspr config set dmg /path/to/file.dmg' >&2
    exit 1
  fi
  dmg_path="$(expand_path "$dmg_path")"

  if [[ ! -f "$dmg_path" ]]; then
    echo "DMG not found: $dmg_path" >&2
    exit 1
  fi

  if is_dmg_mounted "$dmg_path"; then
    echo "DMG already mounted: $dmg_path"
    hdiutil info | awk -v IMG="$dmg_path" '
      $0 ~ /image-path/ && $0 ~ IMG { inimg=1; next }
      inimg && /mount-point/ { print "Mount point: " $2; inimg=0 }
    ' || true
    return 0
  fi

  # Attach without -nobrowse so Finder shows the volume in the sidebar.
  # Capture output to detect the mount point and open it in Finder.
  if out="$(hdiutil attach "$dmg_path")"; then
    echo "Mounted: $dmg_path"

    # Try 1: parse mount point from attach output (line ending with /Volumes/...)
    mp="$(printf "%s\n" "$out" | awk '
      $0 ~ /\/Volumes\// { print $NF; exit }
    ')"

    # Try 2: fallback via hdiutil info for this image path
    if [[ -z "$mp" || ! -d "$mp" ]]; then
      mp="$(hdiutil info | awk -v IMG="$dmg_path" '
        $0 ~ /image-path/ && $0 ~ IMG { inimg=1; next }
        inimg && /mount-point/ { print $2; inimg=0; exit }
      ')"
    fi

    # Try 3: heuristic — newest directory under /Volumes
    if [[ -z "$mp" || ! -d "$mp" ]]; then
      newest="$(ls -1t /Volumes 2>/dev/null | head -n1)"
      if [[ -n "$newest" ]]; then
        mp="/Volumes/$newest"
      else
        mp=""
      fi
    fi

    if [[ -n "$mp" && -d "$mp" ]]; then
      echo "Mount point: $mp"
      open "$mp"
    else
      echo "Mounted, but could not determine mount point automatically." >&2
      echo "Run: hdiutil info  (then open the mount point manually with: open /Volumes/YourVolume)" >&2
    fi
  else
    echo "Failed to mount DMG" >&2
    exit 1
  fi
}

# cmd_unmount_dmg()
# unmount the configured DMG (if mounted), idempotent and quiet
cmd_unmount_dmg() {
  local dmg_path
  if ! dmg_path="$(cmd_config_get dmg 2>/dev/null)"; then
    echo 'Missing config "dmg". Set it with: pspr config set dmg /path/to/file.dmg' >&2
    exit 1
  fi
  dmg_path="$(expand_path "$dmg_path")"

  if ! is_dmg_mounted "$dmg_path"; then
    echo "DMG not mounted: $dmg_path"
    return 0
  fi

  # Prefer a single parent device (e.g., /dev/disk4) and detach once.
  # Fallback to all devices if needed.
  local parent devs
  parent="$(hdiutil info | awk -v IMG="$dmg_path" '
    BEGIN{inimg=0}
    /image-path/ { inimg = (index($0, IMG)>0); next }
    inimg && $1 ~ /^\/dev\/disk[0-9]+$/ { print $1; exit }
  ')"

  # If no parent found, gather all device nodes for this image.
  if [[ -z "$parent" ]]; then
    devs="$(hdiutil info | awk -v IMG="$dmg_path" '
      BEGIN { inimg=0 }
      /image-path/ { inimg = (index($0, IMG)>0); next }
      inimg && $1 ~ /^\/dev\// { print $1 }
      inimg && NF==0 { inimg=0 }
    ')"
  fi

  # Try one clean detach of the parent; if absent, iterate children.
  if [[ -n "$parent" ]]; then
    if hdiutil detach "$parent"; then
      echo "DMG unmounted: $dmg_path"
      return 0
    fi
    # If parent detach failed, try force once.
    if hdiutil detach -force "$parent"; then
      echo "DMG unmounted (forced): $dmg_path"
      return 0
    fi
    echo "Failed to detach $parent" >&2
    # continue to child devices below as a fallback
  fi

  if [[ -z "$devs" && -z "$parent" ]]; then
    # Race: got unmounted between checks
    echo "DMG unmounted: $dmg_path"
    return 0
  fi

  local ok=1
  local tried_any=0

  if [[ -n "$devs" ]]; then
    local d
    for d in ${(f)devs}; do
      tried_any=1
      # Try normal detach; suppress 'No such file or directory' noise
      if ! hdiutil detach "$d" 2> >(grep -v -E 'No such file or directory|Bestand of directory bestaat niet' >&2); then
        # If it failed for other reasons, attempt force once
        if ! hdiutil detach -force "$d" 2> >(grep -v -E 'No such file or directory|Bestand of directory bestaat niet' >&2); then
          # It may already be gone—treat that as success
          if ! hdiutil info | grep -Fq "$d"; then
            continue
          fi
          ok=0
          echo "Failed to detach $d" >&2
        fi
      fi
    done
  fi

  # Final verification: if image no longer listed, consider success
  if ! is_dmg_mounted "$dmg_path"; then
    echo "DMG unmounted: $dmg_path"
    return 0
  fi

  if (( tried_any == 0 )); then
    # Nothing to do (likely already unmounted)
    echo "DMG unmounted: $dmg_path"
    return 0
  fi

  if (( ok )); then
    echo "DMG unmounted: $dmg_path"
  else
    echo "One or more detach operations failed for: $dmg_path" >&2
    exit 1
  fi
}

# cmd_open()
# function to open a folder or file
cmd_open() {
  parse_open_args "$@"

  if [[ "$OPEN_MODE" == "mount" ]]; then
    cmd_mount_dmg
    return
  fi

  local base_path
  if ! base_path="$(cmd_config_get path 2>/dev/null)"; then
    echo 'Missing config "path". Set it with: pspr config set path /your/base/dir' >&2
    exit 1
  fi
  base_path="$(expand_path "$base_path")"

  if [[ "$OPEN_FOLDER" == /* || "$OPEN_FOLDER" == "~"* ]]; then
    echo "foldername should be relative to config path ($base_path), not absolute: $OPEN_FOLDER" >&2
    exit 1
  fi

  local target
  if [[ -n "$OPEN_FILE" ]]; then
    target="$base_path/$OPEN_FOLDER/$OPEN_FILE"
  else
    target="$base_path/$OPEN_FOLDER"
  fi

  if [[ -n "$OPEN_FILE" ]]; then
    [[ -f "$target" ]] || { echo "File not found: $target" >&2; exit 1; }
  else
    [[ -d "$target" ]] || { echo "Folder not found: $target" >&2; exit 1; }
  fi

  require_editor_cli
  open_with_editor "$target"
}

# cmd_close()
# pspr close -> unmount DMG
cmd_close() {
  cmd_unmount_dmg
}

# ---------- SYNC ----------

# cmd_sync()
# pspr sync [--quiet|-q] <foldername>
cmd_sync() {
  local quiet=0
  local folder=""

  # Parse args
  while (( $# > 0 )); do
    case "$1" in
      --quiet|-q)
        quiet=1
        shift
        ;;
      -*)
        echo "Unknown flag: $1" >&2
        echo "Usage: pspr sync [--quiet|-q] <foldername>" >&2
        exit 1
        ;;
      *)
        if [[ -z "$folder" ]]; then
          folder="$1"
          shift
        else
          echo "Too many arguments. Usage: pspr sync [--quiet|-q] <foldername>" >&2
          exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$folder" ]]; then
    echo "Usage: pspr sync [--quiet|-q] <foldername>" >&2
    exit 1
  fi

  # base path from config
  local base_path
  if ! base_path="$(cmd_config_get path 2>/dev/null)"; then
    echo 'Missing config "path". Set it with: pspr config set path /your/base/dir' >&2
    exit 1
  fi
  base_path="$(expand_path "$base_path")"

  if [[ "$folder" == /* || "$folder" == "~"* ]]; then
    echo "foldername should be relative to config path ($base_path), not absolute: $folder" >&2
    exit 1
  fi

  local src="$base_path/$folder"
  if [[ ! -d "$src" ]]; then
    echo "Folder not found: $src" >&2
    exit 1
  fi

  ensure_rclone
  load_config_or_die

  # Build destination: remote:bucket/folder
  local dest="${RCLONE_REMOTE_NAME}:${S3_BUCKET_NAME}/${folder}"

  # Export credentials for providers like R2 when remote references env vars
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_TYPE="s3"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_PROVIDER="Cloudflare"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_REGION="$S3_REGION"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_ENDPOINT="$S3_ENDPOINT"

  # Common rclone args
  local -a common
  common=(
    --fast-list
    --checksum
    --copy-links
    --delete-after
    --track-renames
    --track-renames-strategy hash
    --s3-no-check-bucket
    --s3-provider Cloudflare
    --s3-access-key-id "$S3_ACCESS_KEY_ID"
    --s3-secret-access-key "$S3_SECRET_ACCESS_KEY"
    --s3-region "$S3_REGION"
    --s3-endpoint "$S3_ENDPOINT"
  )

  if (( quiet == 1 )); then
    rclone sync \
      "${common[@]}" \
      --stats-one-line \
      --stats 1m \
      --log-level NOTICE \
      "$src" "$dest"
  else
    rclone sync \
      "${common[@]}" \
      --progress \
      --stats-one-line \
      --stats 10s \
      "$src" "$dest"
  fi
}

# cmd_unsync()
# pspr unsync <foldername> -> delete the folder on remote S3 (no local changes)
cmd_unsync() {
  if (( $# != 1 )); then
    echo "Usage: pspr unsync <foldername>" >&2
    exit 1
  fi
  local folder="$1"

  # Validate folder is relative (same rule as sync)
  local base_path
  if ! base_path="$(cmd_config_get path 2>/dev/null)"; then
    echo 'Missing config "path". Set it with: pspr config set path /your/base/dir' >&2
    exit 1
  fi
  base_path="$(expand_path "$base_path")"

  if [[ "$folder" == /* || "$folder" == "~"* ]]; then
    echo "foldername should be relative to config path ($base_path), not absolute: $folder" >&2
    exit 1
  fi

  ensure_rclone
  load_config_or_die

  # Remote path: remote:bucket/folder
  local remote_path="${RCLONE_REMOTE_NAME}:${S3_BUCKET_NAME}/${folder}"

  # Export credentials for providers like R2 when remote references env vars
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_TYPE="s3"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_PROVIDER="Cloudflare"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_REGION="$S3_REGION"
  export RCLONE_CONFIG_${RCLONE_REMOTE_NAME:u}_ENDPOINT="$S3_ENDPOINT"

  # Remove the entire folder/prefix from remote
  rclone purge \
    --s3-no-check-bucket \
    --s3-provider Cloudflare \
    --s3-access-key-id "$S3_ACCESS_KEY_ID" \
    --s3-secret-access-key "$S3_SECRET_ACCESS_KEY" \
    --s3-region "$S3_REGION" \
    --s3-endpoint "$S3_ENDPOINT" \
    "$remote_path"
}

# ---------- UPDATE ----------

# cmd_update()
# pspr update -> copy pspr.sh from mounted DMG to /usr/local/bin/pspr and make executable
cmd_update() {
  # Require sudo privileges up front to avoid mid-operation prompts/failures
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required to update /usr/local/bin/pspr" >&2
    exit 1
  fi
  if ! sudo -v; then
    echo "sudo authentication failed or not permitted." >&2
    exit 1
  fi

  local dmg_path mp src dst
  if ! dmg_path="$(cmd_config_get dmg 2>/dev/null)"; then
    echo 'Missing config "dmg". Set it with: pspr config set dmg /path/to/file.dmg' >&2
    exit 1
  fi
  dmg_path="$(expand_path "$dmg_path")"

  # Ensure DMG is mounted; if not, try to mount
  if ! is_dmg_mounted "$dmg_path"; then
    cmd_mount_dmg
  fi

  # Determine mount point for this DMG (robust: try attach output-like parse, info, then /Volumes heuristic)
  mp="$(hdiutil info | awk -v IMG="$dmg_path" '
    $0 ~ /image-path/ && $0 ~ IMG { inimg=1; next }
    inimg && /mount-point/ { print $2; inimg=0; exit }
  ')"

  # Fallback 1: some hdiutil info formats place mount point at end of the line
  if [[ -z "$mp" || ! -d "$mp" ]]; then
    mp="$(hdiutil info | awk -v IMG="$dmg_path" '
      $0 ~ /image-path/ && $0 ~ IMG { inimg=1; next }
      inimg && /mount-point/ { print $NF; inimg=0; exit }
    ')"
  fi

  # Fallback 2: if still unknown, pick the newest directory under /Volumes created/modified recently
  if [[ -z "$mp" || ! -d "$mp" ]]; then
    newest="$(ls -1t /Volumes 2>/dev/null | head -n1)"
    if [[ -n "$newest" ]]; then
      mp="/Volumes/$newest"
    fi
  fi

  if [[ -z "$mp" || ! -d "$mp" ]]; then
    echo "Could not determine mount point for: $dmg_path" >&2
    echo "Tip: ensure the DMG is mounted (pspr open), then run: pspr update" >&2
    exit 1
  fi

  src="$mp/pspr.sh"
  if [[ ! -f "$src" ]]; then
    echo "File not found in DMG: $src" >&2
    exit 1
  fi

  dst="/usr/local/bin/pspr"

  # Ensure destination dir exists
  if ! sudo mkdir -p "/usr/local/bin"; then
    echo "Failed to create /usr/local/bin (sudo required)" >&2
    exit 1
  fi

  # Copy and set executable permissions
  if ! sudo install -m 0755 "$src" "$dst"; then
    # Fallback to cp + chmod if install is unavailable
    sudo cp -f "$src" "$dst" && sudo chmod 0755 "$dst" || {
      echo "Failed to install pspr to $dst" >&2
      exit 1
    }
  fi

  echo "Updated: $dst"
}

# ---------- MAIN ----------

# main()
# main function
main() {
  if (( $# < 1 )); then
    usage
    exit 1
  fi

  local cmd="$1"
  shift || true

  case "$cmd" in
    config)
      local sub="${1:-}"
      case "$sub" in
        get)
          if (( $# != 2 )); then usage; exit 1; fi
          shift
          cmd_config_get "$1"
          ;;
        set)
          if (( $# != 3 )); then usage; exit 1; fi
          shift
          cmd_config_set "$1" "$2"
          ;;
        list)
          if (( $# != 1 )); then usage; exit 1; fi
          cmd_config_list
          ;;          
        delete)
          if (( $# != 2 )); then usage; exit 1; fi
          shift
          cmd_config_delete "$1"
          ;;
        reset)
          if (( $# != 1 )); then usage; exit 1; fi
          cmd_config_reset
          ;;     
        *)
          print_logo
          usage; exit 1
          ;;
      esac
      ;;
    open)
      cmd_open "$@"
      ;;
    close)
      cmd_close "$@"
      ;;      
    sync)
      cmd_sync "$@"
      ;;   
    unsync)
      cmd_unsync "$@"
      ;;      
    update)
      cmd_update "$@"
      ;;         
    *)
      print_logo
      usage; exit 1
      ;;
  esac
}

main "$@"