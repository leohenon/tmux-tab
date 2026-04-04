#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/mru.sh"

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value=$(tmux show-option -gqv "$option")
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

cycle_state_file() {
    local server_pid
    server_pid=$(tmux display-message -p '#{pid}')
    echo "/tmp/tmux-tab-cycle-${server_pid}"
}

normalize_cycle_timeout() {
    case "$1" in
    '' | *[!0-9]*)
        echo "2"
        ;;
    *)
        if [ "$1" -lt 1 ]; then
            echo "1"
        else
            echo "$1"
        fi
        ;;
    esac
}

mod_index() {
    local value="$1"
    local size="$2"
    echo $((((value % size) + size) % size))
}

find_index() {
    local needle="$1"
    shift

    local i=0
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            echo "$i"
            return
        fi
        i=$((i + 1))
    done

    echo "-1"
}

direction="${1:-next}"
case "$direction" in
next)
    step=1
    ;;
prev)
    step=-1
    ;;
*)
    step=1
    ;;
esac

readarray -t sessions < <(mru_read)
if [ ${#sessions[@]} -le 1 ]; then
    exit 0
fi

current_session=$(tmux display-message -p '#{session_name}' 2>/dev/null)
if [ -z "$current_session" ]; then
    exit 0
fi

state_file=$(cycle_state_file)
timeout=$(normalize_cycle_timeout "$(get_tmux_option "@tmux-tab-cycle-timeout" "2")")
now=$(date +%s)

target=""
next_index=-1
snapshot=""

if [ -f "$state_file" ]; then
    IFS='|' read -r last_ts last_index stored_sessions < "$state_file"
    if [ -n "$last_ts" ] && [ -n "$last_index" ] && [ -n "$stored_sessions" ]; then
        if [ $((now - last_ts)) -le "$timeout" ]; then
            IFS=$'\t' read -r -a stored_array <<< "$stored_sessions"
            live_target_count=0
            for name in "${stored_array[@]}"; do
                if tmux has-session -t "$name" 2>/dev/null; then
                    live_target_count=$((live_target_count + 1))
                fi
            done

            if [ "$live_target_count" -gt 1 ]; then
                base_index="$last_index"
                if [ "$last_index" -lt 0 ] || [ "$last_index" -ge "${#stored_array[@]}" ] || [ "${stored_array[$last_index]}" != "$current_session" ]; then
                    base_index=$(find_index "$current_session" "${stored_array[@]}")
                fi

                if [ "$base_index" -ge 0 ]; then
                    for ((offset = 1; offset <= ${#stored_array[@]}; offset++)); do
                        candidate_index=$(mod_index "$((base_index + offset * step))" "${#stored_array[@]}")
                        candidate="${stored_array[$candidate_index]}"
                        if [ "$candidate" != "$current_session" ] && tmux has-session -t "$candidate" 2>/dev/null; then
                            target="$candidate"
                            next_index=$candidate_index
                            snapshot="$stored_sessions"
                            break
                        fi
                    done
                fi
            fi
        fi
    fi
fi

if [ -z "$target" ]; then
    current_index=$(find_index "$current_session" "${sessions[@]}")
    if [ "$current_index" -lt 0 ]; then
        current_index=0
    fi

    for ((offset = 1; offset <= ${#sessions[@]}; offset++)); do
        candidate_index=$(mod_index "$((current_index + offset * step))" "${#sessions[@]}")
        candidate="${sessions[$candidate_index]}"
        if [ "$candidate" != "$current_session" ]; then
            target="$candidate"
            next_index=$candidate_index
            snapshot=$(printf '%s\t' "${sessions[@]}")
            snapshot="${snapshot%$'\t'}"
            break
        fi
    done
fi

if [ -z "$target" ]; then
    exit 0
fi

printf '%s|%s|%s\n' "$now" "$next_index" "$snapshot" > "$state_file"
tmux switch-client -t "$target"
