#!/usr/bin/env bash
# get-project-structure (patched, corrected)
# Fixes high-priority issues: removed eval, use safe find argument arrays,
# use mktemp + trap for temp files, null-safe handling of filenames,
# safe per-file filtering for filename ignores, improved error messages,
# and GNU/BSD find size handling.
set -euo pipefail

PROJECT_ROOT="$(pwd)"
OUTPUT_FILE=""
EXTRA_EXCLUDES=()
SHOW_FILES=true
SELECT_PATHS=()
# collect contents into a single text file
DUMP_CONTENTS=false
CONTENTS_FILE=""
# safety options
SKIP_BINARIES=false
MAX_SIZE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [-o output_file] [-e name_or_pattern] [-p path] [-C contents_file] [--compact] [--skip-binaries] [--max-size SIZE]
Options:
  -o, --output FILE         Save tree output to FILE
  -e, --exclude PATTERN     Extra exclude (can be used multiple times). If ends with '/' treated as directory.
  -p, --path PATH           Specific directory or file within project to show (repeatable). If omitted, uses project root.
  -C, --contents-file FILE  Aggregate the contents of all selected files into FILE (saved in project root).
  -B, --skip-binaries       Skip files detected as binary when aggregating contents.
  -M, --max-size SIZE       Skip files larger than SIZE when aggregating contents (e.g. 5M, 500k).
      --compact             Show folders only (no files)
  -h, --help                Show this help
Example:
  get-project-structure
  get-project-structure -o structure.txt
  get-project-structure -e dist/ -e coverage -o s.txt
  get-project-structure --compact
  get-project-structure -p src/ -p docs/
  # Save file contents of selected files into project-files-contents.txt but skip binaries and >5MB files
  get-project-structure -p src/ -C project-files-contents.txt -B -M 5M
Notes:
  - The script honors directory entries ending with '/' from .gitignore (best-effort).
  - When using -C/--contents-file the script will collect regular files only (skips directories),
    applying the same ignore rules as the tree/list operation.
  - Skip behavior:
      - --max-size SIZE uses common suffixes (K, M, G). On non-GNU find, SIZE is translated to bytes and applied with -size +Nc.
      - --skip-binaries uses the 'file' command (preferred). If 'file' is absent, it uses a grep heuristic.
EOF
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -e|--exclude)
      EXTRA_EXCLUDES+=("$2")
      shift 2
      ;;
    -p|--path)
      SELECT_PATHS+=("$2")
      shift 2
      ;;
    -C|--contents-file)
      DUMP_CONTENTS=true
      CONTENTS_FILE="$2"
      shift 2
      ;;
    -B|--skip-binaries)
      SKIP_BINARIES=true
      shift
      ;;
    -M|--max-size)
      MAX_SIZE="$2"
      shift 2
      ;;
    --compact)
      SHOW_FILES=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# default directories to ignore
DIR_IGNORES=( "node_modules" ".next" ".git" )
FILE_IGNORES=()

GITIGNORE="$PROJECT_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  while IFS= read -r rawline || [[ -n "$rawline" ]]; do
    line="${rawline%%#*}"            # strip trailing comment
    line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"  # trim
    [[ -z "$line" ]] && continue
    # If line ends with '/', treat as directory (best-effort)
    if [[ "$line" == */ ]]; then
      entry="${line%/}"
      entry="${entry#./}"
      DIR_IGNORES+=("$entry")
    else
      entry="${line#./}"
      FILE_IGNORES+=("$entry")
    fi
  done < "$GITIGNORE"
fi

# add user-specified excludes
for ex in "${EXTRA_EXCLUDES[@]}"; do
  if [[ "$ex" == */ ]]; then
    ex="${ex%/}"
    DIR_IGNORES+=("$ex")
  elif [[ "$ex" == *'*'* || "$ex" == *'?'* ]]; then
    FILE_IGNORES+=("$ex")
  else
    DIR_IGNORES+=("$ex")
  fi
done

# normalize SELECT_PATHS (remove trailing slashes)
for i in "${!SELECT_PATHS[@]}"; do
  SELECT_PATHS[$i]="${SELECT_PATHS[$i]%/}"
done

# helper: build tree -I pattern (patterns separated by |)
build_tree_pattern() {
  local -n _dirs=$1
  local -n _files=$2
  local pat=""
  for d in "${_dirs[@]}"; do
    if [[ -z "$pat" ]]; then
      pat="$d"
    else
      pat="$pat|$d"
    fi
  done
  for f in "${_files[@]}"; do
    if [[ -z "$pat" ]]; then
      pat="$f"
    else
      pat="$pat|$f"
    fi
  done
  echo "$pat"
}

# helper: build find prune argument array for directories (null-safe args)
build_find_prune_args() {
  local -n _dirs=$1
  PRUNE_ARGS=()
  if [[ ${#_dirs[@]} -eq 0 ]]; then
    return
  fi
  for d in "${_dirs[@]}"; do
    # append as separate array elements to avoid eval and quoting issues
    PRUNE_ARGS+=( -path "*/$d" -prune -o )
  done
}

# helper: build grep regex for file patterns (used in filename matching)
build_grep_regex() {
  local -n _files=$1
  local regex=""
  for f in "${_files[@]}"; do
    safe=$(printf "%s" "$f" | sed -e 's/[.[\^$+?(){}|]/\&/g' -e 's/\*/.*/g' -e 's/\?/./g')
    if [[ -z "$regex" ]]; then
      regex="$safe"
    else
      regex="$regex|$safe"
    fi
  done
  echo "$regex"
}

# helper: detect text files
is_text_file() {
  local file="$1"
  if command -v file &>/dev/null; then
    mime=$(file --mime-type -b -- "$file" 2>/dev/null || echo "")
    if [[ "$mime" == text/* ]]; then
      return 0
    fi
    case "$mime" in
      application/json|application/xml|application/javascript|application/x-sh|application/x-shellscript|application/x-python) return 0 ;;
      *) return 1 ;;
    esac
  else
    if LC_ALL=C grep -Iq . -- "$file" 2>/dev/null; then
      return 0
    else
      return 1
    fi
  fi
}

# helper: human-readable size to bytes (supports K/M/G suffixes, base 1024)
human_to_bytes() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo ""
    return
  fi
  # capture numeric and suffix
  if [[ "$input" =~ ^([0-9]+)([kKmMgG])?$ ]]; then
    num=${BASH_REMATCH[1]}
    suf=${BASH_REMATCH[2]:-}
    case "$suf" in
      [kK]) echo $(( num * 1024 )) ;;
      [mM]) echo $(( num * 1024 * 1024 )) ;;
      [gG]) echo $(( num * 1024 * 1024 * 1024 )) ;;
      "") echo "$num" ;;
      *) echo "$num" ;;
    esac
  else
    # fallback: try to strip non-digits
    digits=$(printf "%s" "$input" | sed -E 's/[^0-9].*//')
    echo "$digits"
  fi
}

# Build patterns
TREE_PATTERN="$(build_tree_pattern DIR_IGNORES FILE_IGNORES)"

# Determine targets
if [[ ${#SELECT_PATHS[@]} -gt 0 ]]; then
  TARGETS=("${SELECT_PATHS[@]}")
else
  TARGETS=(".")
fi

# Choose command path
if command -v tree &>/dev/null; then
  TREE_OPTS=(tree -a)
  if [[ "$SHOW_FILES" = false ]]; then
    TREE_OPTS+=(-d)
  fi
  if [[ -n "$TREE_PATTERN" ]]; then
    TREE_OPTS+=( -I "$TREE_PATTERN" )
  fi
  TREE_OPTS+=("${TARGETS[@]}")

  if [[ -z "$OUTPUT_FILE" ]]; then
    "${TREE_OPTS[@]}"
  else
    "${TREE_OPTS[@]}" > "$OUTPUT_FILE"
    echo "✅ Project structure saved to $OUTPUT_FILE"
  fi
else
  # fallback: use find with PRUNE_ARGS (array) and per-file filtering for FILE_IGNORES
  build_find_prune_args DIR_IGNORES
  GREP_REGEX="$(build_grep_regex FILE_IGNORES)"

  run_find_for_target() {
    local target="$1"
    if [[ ${#PRUNE_ARGS[@]} -eq 0 ]]; then
      find "$target" -print
    else
      find "$target" "${PRUNE_ARGS[@]}" -print
    fi
  }

  if [[ -n "$GREP_REGEX" ]]; then
    if [[ -z "$OUTPUT_FILE" ]]; then
      for t in "${TARGETS[@]}"; do
        run_find_for_target "$t"
      done | grep -Ev "$GREP_REGEX"
    else
      for t in "${TARGETS[@]}"; do
        run_find_for_target "$t"
      done | grep -Ev "$GREP_REGEX" > "$OUTPUT_FILE"
      echo "✅ Project structure saved to $OUTPUT_FILE"
    fi
  else
    if [[ -z "$OUTPUT_FILE" ]]; then
      for t in "${TARGETS[@]}"; do
        run_find_for_target "$t"
      done
    else
      for t in "${TARGETS[@]}"; do
        run_find_for_target "$t"
      done > "$OUTPUT_FILE"
      echo "✅ Project structure saved to $OUTPUT_FILE"
    fi
  fi
fi

# ------------------------------
# Aggregate file contents (safe, null-separated handling)
# ------------------------------
if [[ "$DUMP_CONTENTS" = true ]]; then
  if [[ -z "$CONTENTS_FILE" ]]; then
    echo "Error: contents file not provided. Use -C <filename> or --contents-file <filename>." >&2
    exit 1
  fi

  CONTENTS_FILE_PATH="$PROJECT_ROOT/$CONTENTS_FILE"

  # Build prune args again
  build_find_prune_args DIR_IGNORES
  GREP_REGEX="$(build_grep_regex FILE_IGNORES)"

  # size expression: try to detect GNU find
  SIZE_EXPR=()
  if [[ -n "$MAX_SIZE" ]]; then
    if find --version >/dev/null 2>&1; then
      # GNU find supports size suffixes like 5M
      SIZE_EXPR=( ! -size +${MAX_SIZE} )
    else
      # BSD find: translate to bytes and use -size +Nc (c = bytes)
      BYTES=$(human_to_bytes "$MAX_SIZE")
      if [[ -n "$BYTES" ]]; then
        SIZE_EXPR=( ! -size +${BYTES}c )
      fi
    fi
  fi

  # prepare contents file
  : > "$CONTENTS_FILE_PATH" || { echo "Failed to write to $CONTENTS_FILE_PATH" >&2; exit 1; }

  # tmp file (use mktemp) - ensure cleanup
  TMP_LIST="$(mktemp "${TMPDIR:-/tmp}/gfs_tmp.XXXXXX")"
  trap 'rm -f "$TMP_LIST"' EXIT

  # helper: run find for files (null-separated), applying size filter if set
  run_find_files_for_target() {
    local target="$1"
    local -a find_cmd=(find "$target")
    if [[ ${#PRUNE_ARGS[@]} -gt 0 ]]; then
      find_cmd+=( "${PRUNE_ARGS[@]}" )
    fi
    find_cmd+=( -type f )
    if [[ ${#SIZE_EXPR[@]} -gt 0 ]]; then
      find_cmd+=( "${SIZE_EXPR[@]}" )
    fi
    find_cmd+=( -print0 )
    "${find_cmd[@]}"
  }

  # collect null-separated list into tmp
  for t in "${TARGETS[@]}"; do
    run_find_files_for_target "$t" >> "$TMP_LIST" 2>/dev/null || true
  done

  # Process null-separated file list safely
  if [[ -s "$TMP_LIST" ]]; then
    # iterate files null-safe and apply GREP_REGEX by testing filename string per file
    while IFS= read -r -d '' file; do
      [[ -f "$file" ]] || continue

      # If a filename pattern matches GREP_REGEX, skip
      if [[ -n "$GREP_REGEX" ]]; then
        if printf '%s' "$file" | grep -E -q "$GREP_REGEX"; then
          continue
        fi
      fi

      if [[ "$SKIP_BINARIES" = true ]]; then
        if ! is_text_file "$file"; then
          printf "
----- SKIPPED BINARY: %s -----
" "$file" >> "$CONTENTS_FILE_PATH"
          printf "[Skipped binary file: %s]
" "$file" >> "$CONTENTS_FILE_PATH"
          continue
        fi
      fi

      printf "
----- FILE: %s -----
" "$file" >> "$CONTENTS_FILE_PATH"
      if ! cat -- "$file" >> "$CONTENTS_FILE_PATH" 2>/dev/null; then
        printf "
[Could not read file: %s]
" "$file" >> "$CONTENTS_FILE_PATH"
      fi
    done < "$TMP_LIST"
  fi

  echo "✅ All file contents saved to $CONTENTS_FILE_PATH"
  if [[ "$SKIP_BINARIES" = true ]]; then
    echo "ℹ️  Note: binary files were skipped (per --skip-binaries)."
  fi
  if [[ -n "$MAX_SIZE" ]]; then
    echo "ℹ️  Note: files larger than $MAX_SIZE were excluded (per --max-size)."
  fi
fi
