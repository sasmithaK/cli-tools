#!/usr/bin/env bash
# get-project-structure
# Show project tree while:
#  - ignoring node_modules/ and .next/ by default
#  - honoring .gitignore entries (dir entries ending with '/')
#  - allowing extra excludes via -e/--exclude (can repeat)
#  - optionally saving to an output file (-o/--output)

set -euo pipefail

PROJECT_ROOT="$(pwd)"
OUTPUT_FILE=""
EXTRA_EXCLUDES=()
SHOW_FILES=true

usage() {
  cat <<EOF
Usage: $(basename "$0") [-o output_file] [-e name_or_pattern] [--compact]
Options:
  -o, --output FILE      Save output to FILE
  -e, --exclude PATTERN  Extra exclude (can be used multiple times). If ends with '/' treated as directory.
      --compact          Show folders only (no files)
  -h, --help             Show this help
Example:
  get-project-structure
  get-project-structure -o structure.txt
  get-project-structure -e dist/ -e coverage -o s.txt
  get-project-structure --compact
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
    --compact)
      SHOW_FILES=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# default directories to ignore
DIR_IGNORES=( "node_modules" ".next" )
FILE_IGNORES=()

GITIGNORE="$PROJECT_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  while IFS= read -r rawline || [[ -n "$rawline" ]]; do
    line="${rawline%%#*}"            # strip trailing comment
    line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"  # trim
    [[ -z "$line" ]] && continue
    # If line ends with '/', treat as directory
    if [[ "$line" == */ ]]; then
      entry="${line%/}"
      # ignore leading/trailing glob anchors for simplicity
      entry="${entry#./}"
      DIR_IGNORES+=("$entry")
    else
      # file or pattern (keep as-is for tree -I, will convert for grep fallback)
      entry="${line#./}"
      FILE_IGNORES+=("$entry")
    fi
  done < "$GITIGNORE"
fi

# add user-specified excludes
for ex in "${EXTRA_EXCLUDES[@]}"; do
  # treat entries ending with / as directories
  if [[ "$ex" == */ ]]; then
    ex="${ex%/}"
    DIR_IGNORES+=("$ex")
  elif [[ "$ex" == *'*'* || "$ex" == *'?'* ]]; then
    # contains wildcard -> treat as file pattern
    FILE_IGNORES+=("$ex")
  else
    # treat as directory by default (safer)
    DIR_IGNORES+=("$ex")
  fi
done

# helper: build tree -I pattern (patterns separated by |)
build_tree_pattern() {
  local -n _dirs=$1
  local -n _files=$2
  local pat=""
  for d in "${_dirs[@]}"; do
    # tree matches names; include directory name and also prefix with .*/ to be safe
    if [[ -z "$pat" ]]; then
      pat="$d"
    else
      pat="$pat|$d"
    fi
  done
  for f in "${_files[@]}"; do
    # if the pattern contains a slash, include it as-is; otherwise match filename or glob
    if [[ -z "$pat" ]]; then
      pat="$f"
    else
      pat="$pat|$f"
    fi
  done
  echo "$pat"
}

# helper: build find prune expression for directories
build_find_prune() {
  local -n _dirs=$1
  if [[ ${#_dirs[@]} -eq 0 ]]; then
    echo ""
    return
  fi
  local expr=""
  for d in "${_dirs[@]}"; do
    # prune ./dir and any subpaths
    expr="$expr -path \"./$d\" -prune -o"
  done
  echo "$expr"
}

# helper: build grep regex for file patterns (used in find fallback)
build_grep_regex() {
  local -n _files=$1
  local regex=""
  for f in "${_files[@]}"; do
    # convert simple gitignore globs to basic regex:
    #  - escape dots
    #  - replace '*' -> '.*'
    #  - if pattern contains a slash, match anywhere in path
    safe=$(printf "%s" "$f" | sed -e 's/[.[\^$+?(){}|]/\\&/g' -e 's/\*/.*/g' -e 's/\?/./g')
    if [[ -z "$regex" ]]; then
      regex="$safe"
    else
      regex="$regex|$safe"
    fi
  done
  echo "$regex"
}

# Build patterns
TREE_PATTERN="$(build_tree_pattern DIR_IGNORES FILE_IGNORES)"

# Choose command path
if command -v tree &>/dev/null; then
  # tree available
  # build tree options
  TREE_OPTS=(tree -a)
  if [[ "$SHOW_FILES" = false ]]; then
    TREE_OPTS+=(-d)  # directory-only
  fi
  if [[ -n "$TREE_PATTERN" ]]; then
    TREE_OPTS+=(-I "$TREE_PATTERN")
  fi

  # produce output
  if [[ -z "$OUTPUT_FILE" ]]; then
    "${TREE_OPTS[@]}"
  else
    "${TREE_OPTS[@]}" > "$OUTPUT_FILE"
    echo "✅ Project structure saved to $OUTPUT_FILE"
  fi

else
  # fallback: use find and prune directories, then optionally filter file patterns
  # build prune segments
  PRUNE_EXPR=$(build_find_prune DIR_IGNORES)
  # build grep regex for file patterns
  GREP_REGEX="$(build_grep_regex FILE_IGNORES)"

  # compose find command dynamically (safer to use eval because of -prune segments)
  if [[ -z "$PRUNE_EXPR" ]]; then
    FIND_CMD='find . -print'
  else
    FIND_CMD="eval find . $PRUNE_EXPR -print"
  fi

  # run find and filter file patterns if any
  if [[ -n "$GREP_REGEX" ]]; then
    # print and then grep -Ev the patterns
    if [[ -z "$OUTPUT_FILE" ]]; then
      eval find . $PRUNE_EXPR -print | grep -Ev "$GREP_REGEX"
    else
      eval find . $PRUNE_EXPR -print | grep -Ev "$GREP_REGEX" > "$OUTPUT_FILE"
      echo "✅ Project structure saved to $OUTPUT_FILE"
    fi
  else
    if [[ -z "$OUTPUT_FILE" ]]; then
      eval find . $PRUNE_EXPR -print
    else
      eval find . $PRUNE_EXPR -print > "$OUTPUT_FILE"
      echo "✅ Project structure saved to $OUTPUT_FILE"
    fi
  fi
fi
