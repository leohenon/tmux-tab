#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"
BINARY="$PLUGIN_DIR/bin/switcher"

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

if [ ! -x "$BINARY" ]; then
	tmux display-message "tmux-tab: binary missing. Reload tmux or run scripts/install.sh."
	exit 1
fi

session_count=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d ' ')
if [ "$session_count" -le 1 ]; then
	exit 0
fi

TMUX_BIN=$(command -v tmux)
TMUX_TAB_COLOR=$(get_tmux_option "@tmux-tab-color" "62")
TMUX_TAB_TEXT_COLOR=$(get_tmux_option "@tmux-tab-text-color" "15")

tmux display-popup -E -w "90%" -h "40%" \
	-b rounded -S "fg=#A0A0A0" \
	"/usr/bin/env TMUX_BIN='$TMUX_BIN' TMUX_TAB_COLOR='$TMUX_TAB_COLOR' TMUX_TAB_TEXT_COLOR='$TMUX_TAB_TEXT_COLOR' '$BINARY'"
