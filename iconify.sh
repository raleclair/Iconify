#!/bin/bash

# Icon Generator Script
# Version: 1.1.0
# Description: Generate icons of various sizes for Linux systems, with backup and restore functionality and internationalization.
# License: MIT

set -o pipefail

# Centralized Defaults
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

SUPPORTED_INPUT_FORMATS=("png" "jpg" "jpeg" "svg")
SUPPORTED_OUTPUT_FORMATS=("png" "jpg" "jpeg")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  local LEVEL="$1"
  local MESSAGE="$2"
  local STYLE="${3:-$NC}"

  if $COLOR; then
    echo -e "${STYLE}$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE${NC}" | tee -a "$LOG_FILE"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE" | tee -a "$LOG_FILE"
  fi
}

log_verbose() {
  if $VERBOSE; then
    log "VERBOSE" "$1" "$CYAN"
  fi
}

error_exit() {
  log "ERROR" "$1" "$RED"
  exit 1
}

has_value() {
  [[ -n "${2:-}" && ! "${2}" =~ ^- ]]
}

in_array() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$needle" == "$item" ]] && return 0
  done
  return 1
}

initialize_log_file() {
  if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
  elif [[ "$EUID" -eq 0 ]]; then
    LOG_FILE="/var/log/iconify.log"
  else
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/iconify"
    mkdir -p "$state_dir"
    LOG_FILE="$state_dir/iconify.log"
  fi
  touch "$LOG_FILE" 2>/dev/null || {
    LOG_FILE="/tmp/iconify.log"
    touch "$LOG_FILE" || {
      echo "Unable to create any writable log file." >&2
      exit 1
    }
  }
}

load_translations() {
  local translation_file="locale/$LANGUAGE"
  if [[ -f "$translation_file" ]]; then
    # shellcheck disable=SC1090
    source "$translation_file"
  else
    echo "Translation file not found for language: $LANGUAGE. Falling back to en_US."
    LANGUAGE="en_US"
    # shellcheck disable=SC1091
    source "locale/$LANGUAGE"
  fi
}

validate_sizes() {
  local size
  for size in "${SIZES[@]}"; do
    if ! [[ "$size" =~ ^[1-9][0-9]*$ ]]; then
      error_exit "Invalid size '$size'. Sizes must be positive integers."
    fi
  done
}

validate_options() {
  [[ -d "$SOURCE_FOLDER" ]] || error_exit "Source directory not found: $SOURCE_FOLDER"
  in_array "$OUTPUT_FORMAT" "${SUPPORTED_OUTPUT_FORMATS[@]}" || error_exit "Unsupported output format '$OUTPUT_FORMAT'. Supported: ${SUPPORTED_OUTPUT_FORMATS[*]}"
  validate_sizes
}

check_dependencies() {
  local missing=()

  if command -v magick >/dev/null 2>&1; then
    CONVERT_CMD=(magick)
  elif command -v convert >/dev/null 2>&1; then
    CONVERT_CMD=(convert)
  else
    missing+=("ImageMagick (magick/convert)")
  fi

  if $UPDATE_CACHE; then
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
      CACHE_CMD=(gtk-update-icon-cache)
    elif command -v gtk4-update-icon-cache >/dev/null 2>&1; then
      CACHE_CMD=(gtk4-update-icon-cache)
    else
      missing+=("gtk-update-icon-cache (or gtk4-update-icon-cache)")
    fi
  fi

  if (( ${#missing[@]} > 0 )); then
    error_exit "Missing dependency(s): ${missing[*]}"
  fi
}

check_privileges() {
  if $DRY_RUN; then
    return
  fi

  if [[ -w "$DESTINATION_BASE" ]]; then
    return
  fi

  if [[ "$EUID" -ne 0 ]]; then
    error_exit "Output directory is not writable: $DESTINATION_BASE. Re-run with sudo or choose a user-writable directory."
  fi
}

backup_icon_cache() {
  local timestamp backup_dir backup_file
  timestamp=$(date '+%Y%m%d_%H%M%S')
  backup_dir="$DESTINATION_BASE/backups"
  mkdir -p "$backup_dir"
  backup_file="$backup_dir/icon-theme.cache.$timestamp"

  if [[ -f "$DESTINATION_BASE/icon-theme.cache" ]]; then
    log "INFO" "${MSG_BACKUP_START:-Backing up cache to} $backup_file" "$CYAN"
    cp "$DESTINATION_BASE/icon-theme.cache" "$backup_file"
  else
    log "WARNING" "${MSG_NO_CACHE:-No icon cache found to back up.}" "$YELLOW"
  fi
}

restore_icon_cache() {
  local backup_file
  if [[ -n "$RESTORE_FILE" ]]; then
    backup_file="$RESTORE_FILE"
  else
    backup_file=$(ls -t "$DESTINATION_BASE/backups"/icon-theme.cache.* 2>/dev/null | head -n 1)
  fi

  if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
    error_exit "${MSG_BACKUP_NOT_FOUND:-Backup file not found.}"
  fi

  log "INFO" "${MSG_RESTORE_START:-Restoring backup} $backup_file" "$CYAN"
  cp "$backup_file" "$DESTINATION_BASE/icon-theme.cache"
}

resize_images() {
  shopt -s nullglob
  local size image basename output_file dest_dir

  for size in "${SIZES[@]}"; do
    dest_dir="$DESTINATION_BASE/${size}x${size}/apps"
    mkdir -p "$dest_dir"

    for image in "$SOURCE_FOLDER"/*.{png,jpg,jpeg,svg}; do
      basename=$(basename "$image")
      output_file="$dest_dir/${basename%.*}.$OUTPUT_FORMAT"

      if [[ -f "$output_file" && "$PROMPT_OVERWRITE" == false ]]; then
        log "INFO" "${MSG_OVERWRITE_SKIPPED:-Skipping existing file} $output_file" "$CYAN"
        continue
      elif [[ -f "$output_file" && "$PROMPT_OVERWRITE" == true ]]; then
        read -r -p "${MSG_OVERWRITE_PROMPT:-Overwrite?} $output_file [y/N]: " overwrite
        [[ "$overwrite" =~ ^[Yy]$ ]] || continue
      fi

      log "INFO" "${MSG_PROCESSING_FILE:-Processing} $image -> $output_file" "$CYAN"

      if $DRY_RUN; then
        log "INFO" "${MSG_DRY_RUN_SKIPPED:-Dry-run, skipped writing} $output_file" "$CYAN"
        continue
      fi

      if $SHARPEN; then
        "${CONVERT_CMD[@]}" "$image" -filter "${USE_LANCZOS:+Lanczos}" -resize "${size}x${size}" -sharpen 0x1 "$output_file"
      else
        "${CONVERT_CMD[@]}" "$image" -filter "${USE_LANCZOS:+Lanczos}" -resize "${size}x${size}" "$output_file"
      fi
    done
  done
}

refresh_icon_cache() {
  if $UPDATE_CACHE; then
    log "INFO" "${MSG_UPDATE_CACHE:-Updating icon cache}" "$CYAN"
    if $DRY_RUN; then
      log "INFO" "${MSG_DRY_RUN_SKIPPED:-Dry-run, skipped cache update} $DESTINATION_BASE" "$CYAN"
    else
      "${CACHE_CMD[@]}" -f "$DESTINATION_BASE"
    fi
  else
    log "INFO" "${MSG_SKIP_CACHE_UPDATE:-Skipping icon cache update}" "$CYAN"
  fi
}

display_help() {
  cat <<EOH
${MSG_USAGE:-Usage}: $0 [options]

${MSG_OPTIONS:-Options}:
  --lang <language>          ${MSG_LANG_OPTION:-Set language (default: en_US)}
  -s, --source-dir <dir>     ${MSG_SOURCE_DIR_OPTION:-Source directory (default: current directory)}
  -o, --output-dir <dir>     ${MSG_OUTPUT_DIR_OPTION:-Output directory (default: /usr/share/icons/hicolor)}
  -z, --sizes <list>         ${MSG_SIZES_OPTION:-Comma-separated sizes (default: 8,16,...,512)}
  -f, --output-format <fmt>  ${MSG_OUTPUT_FORMAT_OPTION:-Output format: png|jpg|jpeg}
  -lb, --list-backups        ${MSG_LIST_BACKUPS_OPTION:-List available icon cache backups}
  -rb, --restore-backup [f]  ${MSG_RESTORE_BACKUP_OPTION:-Restore specific or latest backup}
  -x, --sharpen              ${MSG_SHARPEN_OPTION:-Enable extra sharpening}
  -l, --no-lanczos           ${MSG_NO_LANCZOS_OPTION:-Disable Lanczos filter}
  -c, --no-cache-update      ${MSG_NO_CACHE_UPDATE_OPTION:-Skip cache refresh}
  -v, --verbose              ${MSG_VERBOSE_OPTION:-Enable verbose logging}
  -d, --dry-run              ${MSG_DRY_RUN_OPTION:-Preview actions only}
      --no-color             ${MSG_NO_COLOR_OPTION:-Disable color output}
      --log-file <path>      Write logs to custom file
  -V, --version              ${MSG_VERSION_OPTION:-Show script version}
  -h, --help                 Show this help message
EOH
}

main() {
  initialize_log_file
  load_translations
  validate_options
  check_dependencies

  if $LIST_BACKUPS; then
    log "INFO" "${MSG_LISTING_BACKUPS:-Listing backups}"
    ls "$DESTINATION_BASE/backups" 2>/dev/null || true
    exit 0
  fi

  if $RESTORE_CACHE; then
    check_privileges
    log "INFO" "${MSG_RESTORING_BACKUP:-Restoring backup}"
    restore_icon_cache
    exit 0
  fi

  check_privileges
  log "INFO" "${MSG_STARTING_ICON_GENERATION:-Starting icon generation}"
  backup_icon_cache
  resize_images
  refresh_icon_cache
  log "SUCCESS" "${MSG_SUCCESS:-Icon generation completed successfully.}" "$GREEN"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --lang)
      has_value "$1" "$2" || { echo "Missing value for $1" >&2; exit 1; }
      LANGUAGE="$2"; shift 2 ;;
    -s|--source-dir)
      has_value "$1" "$2" || { echo "Missing value for $1" >&2; exit 1; }
      SOURCE_FOLDER="$2"; shift 2 ;;
    -o|--output-dir)
      has_value "$1" "$2" || { echo "Missing value for $1" >&2; exit 1; }
      DESTINATION_BASE="$2"; shift 2 ;;
    -z|--sizes)
      has_value "$1" "$2" || { echo "Missing value for $1" >&2; exit 1; }
      IFS=',' read -r -a SIZES <<< "$2"; shift 2 ;;
    -f|--output-format)
      has_value "$1" "$2" || { echo "Missing value for $1" >&2; exit 1; }
      OUTPUT_FORMAT="$2"; shift 2 ;;
    -lb|--list-backups)
      LIST_BACKUPS=true; shift ;;
    -rb|--restore-backup)
      RESTORE_CACHE=true
      if has_value "$1" "$2"; then RESTORE_FILE="$2"; shift 2; else shift; fi ;;
    -x|--sharpen)
      SHARPEN=true; shift ;;
    -l|--no-lanczos)
      USE_LANCZOS=false; shift ;;
    -c|--no-cache-update)
      UPDATE_CACHE=false; shift ;;
    -v|--verbose)
      VERBOSE=true; shift ;;
    -d|--dry-run)
      DRY_RUN=true; shift ;;
    --no-color)
      COLOR=false; shift ;;
    --log-file)
      has_value "$1" "$2" || { echo "Missing value for $1" >&2; exit 1; }
      LOG_FILE="$2"; shift 2 ;;
    -V|--version)
      echo "${MSG_SCRIPT_VERSION:-Iconify}, Version 1.1.0"; exit 0 ;;
    -h|--help)
      load_translations
      display_help
      exit 0 ;;
    --)
      shift; break ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1 ;;
  esac
done

main
