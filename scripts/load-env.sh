#!/bin/sh

# Load literal configuration assignments without executing .env as shell code.
# This file is sourced by runtime-common.sh after repo_dir has been resolved.

env_file=${EVOLVING_ENV_FILE:-$repo_dir/.env}
[ -f "$env_file" ] || return 0

while IFS= read -r env_line || [ -n "$env_line" ]; do
    case "$env_line" in
        ''|'#'*) continue ;;
        export\ *) env_line=${env_line#export } ;;
    esac

    case "$env_line" in
        *=*) ;;
        *) fail "invalid .env entry (expected KEY=value): $env_line" ;;
    esac

    env_key=${env_line%%=*}
    env_value=${env_line#*=}

    case "$env_key" in
        EVOLVING_*|HF_HUB_DISABLE_XET|HF_HUB_OFFLINE|HF_HOME|XDG_CACHE_HOME) ;;
        *) fail "unsupported .env key: $env_key" ;;
    esac
    case "$env_key" in
        *[!A-Za-z0-9_]*|'') fail "invalid .env key: $env_key" ;;
    esac

    case "$env_value" in
        \"*\") env_value=${env_value#\"}; env_value=${env_value%\"} ;;
        \'*\') env_value=${env_value#\'}; env_value=${env_value%\'} ;;
    esac

    eval "env_is_set=\${$env_key+x}"
    if [ -z "$env_is_set" ]; then
        export "$env_key=$env_value"
    fi
done <"$env_file"

unset env_file env_line env_key env_value env_is_set
