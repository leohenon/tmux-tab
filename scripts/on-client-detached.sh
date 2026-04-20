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

hook_client="${1:-}"
if [ "$(get_tmux_option "@tmux-tab-reset-on-detach" "off")" != "on" ]; then
	exit 0
fi

remaining_clients=$(tmux list-clients -F '#{client_name}' 2>/dev/null | grep -Fxv -- "$hook_client" | wc -l | tr -d ' ')
if [ "$remaining_clients" -gt 0 ]; then
	exit 0
fi

rm -f "$(mru_file)" "$(cycle_state_file)"
