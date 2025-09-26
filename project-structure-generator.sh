#!/bin/bash
# Generate a clean project tree with ignore support

PROJECT_ROOT=$(pwd)
OUTPUT_FILE=""
EXTRA_EXCLUDES=()

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE=$2
            shift 2
            ;;
        -e|--exclude)
            EXTRA_EXCLUDES+=("$2")
            shift 2
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Usage: $0 [-o output_file] [-e folder_to_exclude]"
            exit 1
            ;;
    esac
done

# --- Build exclusion list from .gitignore ---
EXCLUDES=()
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        # Normalize trailing slashes
        line="${line%/}"
        EXCLUDES+=("--prune" "-I" "$line")
    done < "$PROJECT_ROOT/.gitignore"
fi

# Add extra excludes
for ex in "${EXTRA_EXCLUDES[@]}"; do
    EXCLUDES+=("--prune" "-I" "$ex")
done

# --- Generate tree ---
if command -v tree &>/dev/null; then
    CMD=(tree -a -I ".gitignore")
    # Add excludes for tree
    for ex in "${EXTRA_EXCLUDES[@]}"; do
        CMD+=("-I" "$ex")
    done
    # tree doesn’t directly support .gitignore so we manually add above
else
    echo "⚠️  'tree' not found, falling back to 'find'"
    CMD=(find .)
fi

# --- Run and output ---
if [ -z "$OUTPUT_FILE" ]; then
    "${CMD[@]}"
else
    "${CMD[@]}" > "$OUTPUT_FILE"
    echo "✅ Project structure saved to $OUTPUT_FILE"
fi
