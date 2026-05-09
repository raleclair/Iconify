#!/bin/bash

# Icon Generator Script
# Version: 1.2.0

set -o pipefail

DEFAULT_SOURCE_FOLDER=$(pwd)
DEFAULT_DESTINATION_BASE="/usr/share/icons/hicolor"
DEFAULT_SIZES=(8 16 22 24 28 32 36 42 48 64 72 96 128 192 256 512)
DEFAULT_OUTPUT_FORMAT="png"
DEFAULT_SHARPEN=false
DEFAULT_USE_LANCZOS=true
DEFAULT_UPDATE_CACHE=true
DEFAULT_VERBOSE=false
DEFAULT_DRY_RUN=false
DEFAULT_LIST_BACKUPS=false
DEFAULT_RESTORE_CACHE=false
DEFAULT_RESTORE_FILE=""
DEFAULT_COLOR=true
DEFAULT_LANGUAGE="en_US"
DEFAULT_PROMPT_OVERWRITE=false
DEFAULT_LOG_FILE=""
DEFAULT_INSTALL_ICONS="all"
DEFAULT_LIST_INSTALLED=false
DEFAULT_EXPORT_GROUP=""
DEFAULT_IMPORT_REPO=""
DEFAULT_THEME_NAME="hicolor"

SOURCE_FOLDER="$DEFAULT_SOURCE_FOLDER"
DESTINATION_BASE="$DEFAULT_DESTINATION_BASE"
SIZES=("${DEFAULT_SIZES[@]}")
OUTPUT_FORMAT="$DEFAULT_OUTPUT_FORMAT"
SHARPEN=$DEFAULT_SHARPEN
USE_LANCZOS=$DEFAULT_USE_LANCZOS
UPDATE_CACHE=$DEFAULT_UPDATE_CACHE
VERBOSE=$DEFAULT_VERBOSE
DRY_RUN=$DEFAULT_DRY_RUN
LIST_BACKUPS=$DEFAULT_LIST_BACKUPS
RESTORE_CACHE=$DEFAULT_RESTORE_CACHE
RESTORE_FILE="$DEFAULT_RESTORE_FILE"
COLOR=$DEFAULT_COLOR
LANGUAGE="$DEFAULT_LANGUAGE"
PROMPT_OVERWRITE=$DEFAULT_PROMPT_OVERWRITE
LOG_FILE="$DEFAULT_LOG_FILE"
INSTALL_ICONS="$DEFAULT_INSTALL_ICONS"
LIST_INSTALLED=$DEFAULT_LIST_INSTALLED
EXPORT_GROUP="$DEFAULT_EXPORT_GROUP"
IMPORT_REPO="$DEFAULT_IMPORT_REPO"
THEME_NAME="$DEFAULT_THEME_NAME"

SUPPORTED_OUTPUT_FORMATS=("png" "jpg" "jpeg")
SUPPORTED_INPUT_FORMATS=("png" "jpg" "jpeg" "svg")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log(){ local LEVEL="$1"; local MESSAGE="$2"; local STYLE="${3:-$NC}"; if $COLOR; then echo -e "${STYLE}$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE${NC}" | tee -a "$LOG_FILE"; else echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE" | tee -a "$LOG_FILE"; fi; }
error_exit(){ log "ERROR" "$1" "$RED"; exit 1; }
has_value(){ [[ -n "${2:-}" && ! "${2}" =~ ^- ]]; }
in_array(){ local n="$1"; shift; local i; for i in "$@"; do [[ "$n" == "$i" ]] && return 0; done; return 1; }

initialize_log_file(){ if [[ -n "$LOG_FILE" ]]; then mkdir -p "$(dirname "$LOG_FILE")"; elif [[ "$EUID" -eq 0 ]]; then LOG_FILE="/var/log/iconify.log"; else local d="${XDG_STATE_HOME:-$HOME/.local/state}/iconify"; mkdir -p "$d"; LOG_FILE="$d/iconify.log"; fi; touch "$LOG_FILE" 2>/dev/null || { LOG_FILE="/tmp/iconify.log"; touch "$LOG_FILE" || { echo "Unable to create any writable log file." >&2; exit 1; }; }; }
load_translations(){ local f="locale/$LANGUAGE"; if [[ -f "$f" ]]; then source "$f"; else LANGUAGE="en_US"; source "locale/$LANGUAGE"; fi; }

parse_icon_selection(){
  local lower
  lower=$(echo "$INSTALL_ICONS" | tr '[:upper:]' '[:lower:]')
  if [[ "$lower" == "all" ]]; then
    SELECTED_ICONS=()
  else
    IFS=',' read -r -a SELECTED_ICONS <<< "$INSTALL_ICONS"
    local idx
    for idx in "${!SELECTED_ICONS[@]}"; do
      SELECTED_ICONS[$idx]="$(echo "${SELECTED_ICONS[$idx]}" | xargs)"
      [[ -n "${SELECTED_ICONS[$idx]}" ]] || error_exit "Invalid empty icon name in --install-icons list."
    done
  fi
}

validate_options(){
  [[ -d "$SOURCE_FOLDER" ]] || error_exit "Source directory not found: $SOURCE_FOLDER"
  in_array "$OUTPUT_FORMAT" "${SUPPORTED_OUTPUT_FORMATS[@]}" || error_exit "Unsupported output format '$OUTPUT_FORMAT'."
  parse_icon_selection
}

check_dependencies(){
  local missing=()
  if command -v magick >/dev/null 2>&1; then CONVERT_CMD=(magick); elif command -v convert >/dev/null 2>&1; then CONVERT_CMD=(convert); else missing+=("ImageMagick"); fi
  if $UPDATE_CACHE; then
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then CACHE_CMD=(gtk-update-icon-cache); elif command -v gtk4-update-icon-cache >/dev/null 2>&1; then CACHE_CMD=(gtk4-update-icon-cache); else missing+=("gtk-update-icon-cache"); fi
  fi
  (( ${#missing[@]} == 0 )) || error_exit "Missing dependency(s): ${missing[*]}"
}

list_installed_icons(){
  local d="$DESTINATION_BASE"
  [[ -d "$d" ]] || error_exit "Output directory not found: $d"
  find "$d" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -path "*/apps/*" -printf "%f\n" | sed 's/\.[^.]*$//' | sort -u
}

import_icon_repository(){
  [[ -n "$IMPORT_REPO" ]] || return
  [[ -d "$IMPORT_REPO" ]] || error_exit "Import path does not exist: $IMPORT_REPO"
  log "INFO" "Importing source icons from $IMPORT_REPO" "$CYAN"
  if ! $DRY_RUN; then
    cp -a "$IMPORT_REPO"/. "$SOURCE_FOLDER"/
  fi
}

resize_images(){
  shopt -s nullglob
  local size image base out dest
  local images=("$SOURCE_FOLDER"/*.{png,jpg,jpeg,svg})
  (( ${#images[@]} > 0 )) || error_exit "No source icons found in $SOURCE_FOLDER"

  for size in "${SIZES[@]}"; do
    dest="$DESTINATION_BASE/${size}x${size}/apps"
    mkdir -p "$dest"
    for image in "${images[@]}"; do
      base="$(basename "$image")"
      base="${base%.*}"
      if (( ${#SELECTED_ICONS[@]} > 0 )) && ! in_array "$base" "${SELECTED_ICONS[@]}"; then
        continue
      fi
      out="$dest/$base.$OUTPUT_FORMAT"
      log "INFO" "Processing $image -> $out" "$CYAN"
      $DRY_RUN && continue
      if $SHARPEN; then "${CONVERT_CMD[@]}" "$image" -filter "${USE_LANCZOS:+Lanczos}" -resize "${size}x${size}" -sharpen 0x1 "$out"; else "${CONVERT_CMD[@]}" "$image" -filter "${USE_LANCZOS:+Lanczos}" -resize "${size}x${size}" "$out"; fi
    done
  done
}

export_icon_group(){
  [[ -n "$EXPORT_GROUP" ]] || return
  local target="$EXPORT_GROUP"
  mkdir -p "$target"
  log "INFO" "Exporting generated icons to $target" "$CYAN"
  if ! $DRY_RUN; then
    cp -a "$DESTINATION_BASE" "$target/"
  fi
}

refresh_icon_cache(){
  if $UPDATE_CACHE; then $DRY_RUN || "${CACHE_CMD[@]}" -f "$DESTINATION_BASE"; fi
}

display_help(){ cat <<EOH
Usage: $0 [options]
  -s, --source-dir <dir>
  -o, --output-dir <dir>
  -z, --sizes <list>
  -f, --output-format <fmt>
      --install-icons <list|all>  Install comma-separated icon names or all (default)
      --list-installed-icons       List currently installed icon names in output dir
      --import-icon-repo <dir>     Import icons from another local repository path
      --export-group <dir>         Export generated icon tree to target directory
      --theme-name <name>          Icon theme name for logging/context (default: hicolor)
  -d, --dry-run
  -h, --help
EOH
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --lang) LANGUAGE="$2"; shift 2 ;;
    -s|--source-dir) SOURCE_FOLDER="$2"; shift 2 ;;
    -o|--output-dir) DESTINATION_BASE="$2"; shift 2 ;;
    -z|--sizes) IFS=',' read -r -a SIZES <<< "$2"; shift 2 ;;
    -f|--output-format) OUTPUT_FORMAT="$2"; shift 2 ;;
    --install-icons) INSTALL_ICONS="$2"; shift 2 ;;
    --list-installed-icons) LIST_INSTALLED=true; shift ;;
    --import-icon-repo) IMPORT_REPO="$2"; shift 2 ;;
    --export-group) EXPORT_GROUP="$2"; shift 2 ;;
    --theme-name) THEME_NAME="$2"; shift 2 ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    -c|--no-cache-update) UPDATE_CACHE=false; shift ;;
    -h|--help) display_help; exit 0 ;;
    *) shift ;;
  esac
done

initialize_log_file
load_translations
validate_options
check_dependencies

if $LIST_INSTALLED; then
  list_installed_icons
  exit 0
fi

import_icon_repository
resize_images
refresh_icon_cache
export_icon_group
log "SUCCESS" "Icon generation completed for theme: $THEME_NAME" "$GREEN"
