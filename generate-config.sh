#!/usr/bin/env bash
set -e

RESET='\e[0m'
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'

TEMPLATES_DIR="${TEMPLATES_DIR:-/templates}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
TEMPLATE_PATTERN="${TEMPLATE_PATTERN:-*.template}"

echo "=== Config Generator Started ==="
echo "Templates directory: $TEMPLATES_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Template pattern: $TEMPLATE_PATTERN"
echo "================================"

mkdir -p "$OUTPUT_DIR"

# Extract ${VAR} references from a template and build the envsubst variable list.
# This prevents envsubst from clobbering variables used natively by the target
# application (e.g. nginx's $uri, $host) and avoids leaking unrelated env vars.
extract_vars() {
    grep -oE '\$\{[A-Za-z_][A-Za-z_0-9]*\}' "$1" 2>/dev/null | sort -u | tr '\n' ' '
}

if [ -n "$(find "$TEMPLATES_DIR" -name "$TEMPLATE_PATTERN" 2>/dev/null)" ]; then
    for template_file in "$TEMPLATES_DIR"/$TEMPLATE_PATTERN; do
        if [ -f "$template_file" ]; then
            filename=$(basename "$template_file")
            output_name="${filename%.template}"
            output_path="$OUTPUT_DIR/$output_name"
            
            echo "Processing: $filename -> $output_name"
            
            # Check if output path already exists as a directory
            # Docker compose sometimes creates these if you try to mount
            # a file before it was created
            if [ -d "$output_path" ]; then
                # Check if directory is empty
                if [ -n "$(find "$output_path" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
                    printf "%b\n" "${RED}Error: $output_path exists as non-empty directory. Cannot overwrite.${RESET}"
                    printf "%b\n" "${RED}Please ensure the output directory is clean before running the config generator.${RESET}"
                    exit 1
                else
                    echo "Warning: $output_path exists as empty directory, removing it..."
                    rmdir "$output_path"
                fi
            fi
            
            # Only substitute variables that are explicitly referenced in the template
            var_list=$(extract_vars "$template_file")
            
            if [ -z "$var_list" ]; then
                printf "%b\n" "${YELLOW}Warning: $filename contains no \${VAR} references, copying as-is${RESET}"
                cp "$template_file" "$output_path"
            else
                # Warn about any referenced variables that are not set
                has_unset=false
                for var_ref in $var_list; do
                    var_name="${var_ref#\$\{}"
                    var_name="${var_name%\}}"
                    if [ -z "${!var_name+x}" ]; then
                        printf "%b\n" "${YELLOW}Warning: $filename references \${$var_name} but it is not set (will be empty)${RESET}"
                        has_unset=true
                    fi
                done
                
                if [ "${STRICT:-false}" = "true" ] && [ "$has_unset" = "true" ]; then
                    printf "%b\n" "${RED}Error: unset variables in $filename and STRICT=true, aborting${RESET}"
                    exit 1
                fi
                
                envsubst "$var_list" < "$template_file" > "$output_path"
            fi
            
            echo "Generated: $output_path"
            
            if [ "${DEBUG:-false}" = "true" ]; then
                echo "--- Content preview (first 5 lines, values redacted) ---"
                head -5 "$output_path" | sed -E 's/([Pp]ass(word)?|[Ss]ecret|[Tt]oken|[Kk]ey)[[:space:]]*[:=][[:space:]]*.+/\1: ******/g'
                echo "--- End preview ---"
            fi
        fi
    done
else
    printf "%b\n" "${RED}No template files found matching pattern: $TEMPLATE_PATTERN${RESET}"
    exit 1
fi

printf "%b\n" "${GREEN}=== Config Generation Completed ===${RESET}"

if [ "${KEEP_RUNNING}" = "true" ]; then
    echo "Keeping container running for debugging..."
    tail -f /dev/null
fi