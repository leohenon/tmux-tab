#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

main() {
    local bind_key
    local binary
    local cycle_bind_key
    local cycle_prev_bind_key
    local cycle_use_prefix
    local use_prefix
    binary="$CURRENT_DIR/bin/switcher"
    bind_key=$(get_tmux_option "@tmux-tab-bind" "Tab")
    cycle_bind_key=$(get_tmux_option "@tmux-tab-cycle-bind" "")
    cycle_prev_bind_key=$(get_tmux_option "@tmux-tab-cycle-prev-bind" "")
    cycle_use_prefix=$(get_tmux_option "@tmux-tab-cycle-prefix" "on")
    use_prefix=$(get_tmux_option "@tmux-tab-prefix" "on")

    if [ ! -x "$binary" ]; then
        if ! "$CURRENT_DIR/scripts/install.sh"; then
            return 1
        fi
    fi

    tmux set-hook -gu session-created 2>/dev/null

    tmux set-hook -g client-session-changed \
        "run-shell -b '$CURRENT_DIR/scripts/on-session-changed.sh'"

    tmux set-hook -g client-detached \
        "run-shell -b '$CURRENT_DIR/scripts/on-client-detached.sh \"#{hook_client}\"'"

    tmux run-shell -b "$CURRENT_DIR/scripts/on-session-changed.sh"

    tmux unbind-key -T root "$bind_key" 2>/dev/null
    tmux unbind-key -T prefix "$bind_key" 2>/dev/null
    tmux unbind-key -T prefix Tab 2>/dev/null

    if [ -n "$cycle_bind_key" ]; then
        tmux unbind-key -T root "$cycle_bind_key" 2>/dev/null
        tmux unbind-key -T prefix "$cycle_bind_key" 2>/dev/null
    fi

    if [ -n "$cycle_prev_bind_key" ]; then
        tmux unbind-key -T root "$cycle_prev_bind_key" 2>/dev/null
        tmux unbind-key -T prefix "$cycle_prev_bind_key" 2>/dev/null
    fi

    if [ "$use_prefix" = "on" ]; then
        tmux bind-key "$bind_key" \
            run-shell "$CURRENT_DIR/scripts/launch.sh"
    else
        tmux bind-key -n "$bind_key" \
            run-shell "$CURRENT_DIR/scripts/launch.sh"
    fi

    if [ -n "$cycle_bind_key" ]; then
        if [ "$cycle_use_prefix" = "on" ]; then
            tmux bind-key "$cycle_bind_key" \
                run-shell "$CURRENT_DIR/scripts/cycle.sh next"
        else
            tmux bind-key -n "$cycle_bind_key" \
                run-shell "$CURRENT_DIR/scripts/cycle.sh next"
        fi
    fi

    if [ -n "$cycle_prev_bind_key" ]; then
        if [ "$cycle_use_prefix" = "on" ]; then
            tmux bind-key "$cycle_prev_bind_key" \
                run-shell "$CURRENT_DIR/scripts/cycle.sh prev"
        else
            tmux bind-key -n "$cycle_prev_bind_key" \
                run-shell "$CURRENT_DIR/scripts/cycle.sh prev"
        fi
    fi
}

main
