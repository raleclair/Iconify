#!/bin/bash

# Icon Generator Script
# Version: 1.0.0
# Author: Your Name
# Description: Generate icons of various sizes for Linux systems, with backup and restore functionality and internationalization.
# License: MIT

# Centralized Defaults
DEFAULT_SOURCE_FOLDER=$(pwd)  # Current directory
DEFAULT_DESTINATION_BASE="/usr/share/icons/hicolor"
DEFAULT_SIZES=(8 16 22 24 28 32 36 42 48 64 72 96 128 192 256 512)
DEFAULT_OUTPUT_FORMAT="png"
DEFAULT_SHARPEN=false
DEFAULT_USE_LANCZOS=true
DEFAULT_UPDATE_CACHE=true
DEFAULT_VERBOSE=false
DEFAULT_SKIP_CHECKS=false
DEFAULT_PROMPT_OVERWRITE=false
DEFAULT_DRY_RUN=false
DEFAULT_LIST_BACKUPS=false
DEFAULT_RESTORE_CACHE=false
DEFAULT_RESTORE_FILE=""  # Use the most recent backup if not specified
DEFAULT_COLOR=true
DEFAULT_LANGUAGE="en_US"

# Initialize Variables
SOURCE_FOLDER="$DEFAULT_SOURCE_FOLDER"
DESTINATION_BASE="$DEFAULT_DESTINATION_BASE"
SIZES=("${DEFAULT_SIZES[@]}")
OUTPUT_FORMAT="$DEFAULT_OUTPUT_FORMAT"
SHARPEN=$DEFAULT_SHARPEN
USE_LANCZOS=$DEFAULT_USE_LANCZOS
UPDATE_CACHE=$DEFAULT_UPDATE_CACHE
VERBOSE=$DEFAULT_VERBOSE
SKIP_CHECKS=$DEFAULT_SKIP_CHECKS
PROMPT_OVERWRITE=$DEFAULT_PROMPT_OVERWRITE
DRY_RUN=$DEFAULT_DRY_RUN
LIST_BACKUPS=$DEFAULT_LIST_BACKUPS
RESTORE_CACHE=$DEFAULT_RESTORE_CACHE
RESTORE_FILE="$DEFAULT_RESTORE_FILE"
COLOR=$DEFAULT_COLOR
LANGUAGE="$DEFAULT_LANGUAGE"

# Supported Formats
SUPPORTED_INPUT_FORMATS=("png" "jpg" "jpeg" "svg")
SUPPORTED_OUTPUT_FORMATS=("png" "jpg" "jpeg")

# ANSI Colors and Styles
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging Function
log() {
  local LEVEL="$1"
  local MESSAGE="$2"
  local STYLE="${3:-$NC}" # Default to no style

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

# Load Translations
load_translations() {
  local TRANSLATION_FILE="locale/$LANGUAGE"
  if [ -f "$TRANSLATION_FILE" ]; then
    source "$TRANSLATION_FILE"
  else
    echo "Translation file not found for language: $LANGUAGE. Falling back to en_US."
    LANGUAGE="en_US"
    source "locale/$LANGUAGE"
  fi
}

# Ensure the script is run as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "$MSG_RUN_AS_ROOT"
    exit 1
  fi
}

# Create Backup of Icon Cache
backup_icon_cache() {
  local TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
  local BACKUP_DIR="$DESTINATION_BASE/backups"
  mkdir -p "$BACKUP_DIR"
  local BACKUP_FILE="$BACKUP_DIR/icon-theme.cache.$TIMESTAMP"

  if [ -f "$DESTINATION_BASE/icon-theme.cache" ]; then
    log "INFO" "$MSG_BACKUP_START $BACKUP_FILE" "$CYAN"
    cp "$DESTINATION_BASE/icon-theme.cache" "$BACKUP_FILE"
  else
    log "WARNING" "$MSG_NO_CACHE" "$YELLOW"
  fi
}

# Restore Icon Cache
restore_icon_cache() {
  local BACKUP_FILE="${RESTORE_FILE:-$(ls -t "$DESTINATION_BASE/backups"/icon-theme.cache.* 2>/dev/null | head -n 1)}"
  if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
    log "ERROR" "$MSG_BACKUP_NOT_FOUND" "$RED"
    exit 1
  fi

  log "INFO" "$MSG_RESTORE_START $BACKUP_FILE" "$CYAN"
  cp "$BACKUP_FILE" "$DESTINATION_BASE/icon-theme.cache"
}

# Resize Images
resize_images() {
  for SIZE in "${SIZES[@]}"; do
    local DEST_DIR="$DESTINATION_BASE/${SIZE}x${SIZE}/apps"
    mkdir -p "$DEST_DIR"

    for IMAGE in "$SOURCE_FOLDER"/*.{${SUPPORTED_INPUT_FORMATS[*]}}; do
      [ -e "$IMAGE" ] || continue
      local BASENAME=$(basename "$IMAGE")
      local OUTPUT_FILE="$DEST_DIR/${BASENAME%.*}.$OUTPUT_FORMAT"

      if [ -f "$OUTPUT_FILE" ] && ! $PROMPT_OVERWRITE; then
        log "INFO" "$MSG_OVERWRITE_SKIPPED $OUTPUT_FILE" "$CYAN"
        continue
      elif [ -f "$OUTPUT_FILE" ] && $PROMPT_OVERWRITE; then
        read -p "$MSG_OVERWRITE_PROMPT $OUTPUT_FILE [y/N]: " OVERWRITE
        [[ "$OVERWRITE" =~ ^[Yy]$ ]] || continue
      fi

      log "INFO" "$MSG_PROCESSING_FILE $IMAGE -> $OUTPUT_FILE" "$CYAN"

      if $DRY_RUN; then
        log "INFO" "$MSG_DRY_RUN_SKIPPED $OUTPUT_FILE" "$CYAN"
      else
        if $SHARPEN; then
          convert "$IMAGE" -filter "${USE_LANCZOS:+Lanczos}" -resize "${SIZE}x${SIZE}" -sharpen 0x1 "$OUTPUT_FILE"
        else
          convert "$IMAGE" -filter "${USE_LANCZOS:+Lanczos}" -resize "${SIZE}x${SIZE}" "$OUTPUT_FILE"
        fi
      fi
    done
  done
}

# Refresh Icon Cache
refresh_icon_cache() {
  if $UPDATE_CACHE; then
    log "INFO" "$MSG_UPDATE_CACHE" "$CYAN"
    gtk-update-icon-cache -f "$DESTINATION_BASE"
  else
    log "INFO" "$MSG_SKIP_CACHE_UPDATE" "$CYAN"
  fi
}

# Display Help Message
display_help() {
  echo "$MSG_USAGE: $0 [options]"
  echo ""
  echo "$MSG_OPTIONS:"
  echo "  --lang <language>          $MSG_LANG_OPTION"
  echo "  -s, --source-dir          $MSG_SOURCE_DIR_OPTION"
  echo "  -o, --output-dir          $MSG_OUTPUT_DIR_OPTION"
  echo "  -z, --sizes               $MSG_SIZES_OPTION"
  echo "  -f, --output-format       $MSG_OUTPUT_FORMAT_OPTION"
  echo "  -lb, --list-backups       $MSG_LIST_BACKUPS_OPTION"
  echo "  -rb, --restore-backup     $MSG_RESTORE_BACKUP_OPTION"
  echo "  -x, --sharpen             $MSG_SHARPEN_OPTION"
  echo "  -l, --no-lanczos          $MSG_NO_LANCZOS_OPTION"
  echo "  -c, --no-cache-update     $MSG_NO_CACHE_UPDATE_OPTION"
  echo "  -v, --verbose             $MSG_VERBOSE_OPTION"
  echo "  -d, --dry-run             $MSG_DRY_RUN_OPTION"
  echo "      --no-color            $MSG_NO_COLOR_OPTION"
  echo "  -V, --version             $MSG_VERSION_OPTION"
  echo ""
  echo "$MSG_EXAMPLES:"
  echo "  1. $MSG_EXAMPLE_DEFAULT: sudo $0"
  echo "  2. $MSG_EXAMPLE_SIZES: sudo $0 -z 16,32,48"
  echo "  3. $MSG_EXAMPLE_BACKUP: sudo $0 -lb"
  echo "  4. $MSG_EXAMPLE_RESTORE: sudo $0 -rb"
  echo "  5. $MSG_EXAMPLE_DRY_RUN: sudo $0 -d"
  echo ""
}

# Main Logic
main() {
  if $LIST_BACKUPS; then
    log "INFO" "$MSG_LISTING_BACKUPS"
    ls "$DESTINATION_BASE/backups"
    exit 0
  fi

  if $RESTORE_CACHE; then
    log "INFO" "$MSG_RESTORING_BACKUP"
    restore_icon_cache
    exit 0
  fi

  log "INFO" "$MSG_STARTING_ICON_GENERATION"
  backup_icon_cache
  resize_images
  refresh_icon_cache
  log "SUCCESS" "$MSG_SUCCESS"
}

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --lang) LANGUAGE="$2"; shift 2 ;;
    -s|--source-dir) SOURCE_FOLDER="$2"; shift 2 ;;
    -o|--output-dir) DESTINATION_BASE="$2"; shift 2 ;;
    -z|--sizes) IFS=',' read -r -a SIZES <<< "$2"; shift 2 ;;
    -f|--output-format) OUTPUT_FORMAT="$2"; shift 2 ;;
    -lb|--list-backups) LIST_BACKUPS=true; shift ;;
    -rb|--restore-backup) RESTORE_CACHE=true; RESTORE_FILE="$2"; shift 2 ;;
    -x|--sharpen) SHARPEN=true; shift ;;
    -l|--no-lanczos) USE_LANCZOS=false; shift ;;
    -c|--no-cache-update) UPDATE_CACHE=false; shift ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    --no-color) COLOR=false; shift ;;
    -V|--version) echo "$MSG_SCRIPT_VERSION, Version 1.0.0"; exit 0 ;;
    -h|--help) display_help; exit 0 ;;
    *) log "ERROR" "$MSG_UNKNOWN_OPTION $1"; exit 1 ;;
  esac
done

# Load Translations and Execute
load_translations
check_root
main
