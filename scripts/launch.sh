#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"
BINARY="$PLUGIN_DIR/bin/switcher"
source "$CURRENT_DIR/mru.sh"

min() {
	if [ "$1" -lt "$2" ]; then
		echo "$1"
	else
		echo "$2"
	fi
}

max() {
	if [ "$1" -gt "$2" ]; then
		echo "$1"
	else
		echo "$2"
	fi
}

normalize_max_tabs() {
	case "$1" in
	'' | *[!0-9]*)
		echo "8"
		return
		;;
	esac

	if [ "$1" -lt 5 ]; then
		echo "5"
	elif [ "$1" -gt 12 ]; then
		echo "12"
	else
		echo "$1"
	fi
}

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

readarray -t sessions < <(mru_read)
session_count=${#sessions[@]}
if [ "$session_count" -le 1 ]; then
	tmux display-message "No recent sessions"
	exit 0
fi

TMUX_BIN=$(command -v tmux)
TMUX_TAB_COLOR=$(get_tmux_option "@tmux-tab-color" "62")
TMUX_TAB_TEXT_COLOR=$(get_tmux_option "@tmux-tab-text-color" "15")
TMUX_TAB_MAX_TABS=$(normalize_max_tabs "$(get_tmux_option "@tmux-tab-max-tabs" "7")")

client_w=$(tmux display-message -p '#{client_width}')
client_h=$(tmux display-message -p '#{client_height}')

visible_tabs=$(min "$session_count" "$TMUX_TAB_MAX_TABS")
if [ "$visible_tabs" -gt 5 ]; then
	rows=2
else
	rows=1
fi
cols=$(((visible_tabs + rows - 1) / rows))

gap=1
frame=2
ideal_card_w=46

max_popup_w=$((client_w - 4))
max_popup_w=$(max "$max_popup_w" 1)
ideal_popup_w=$((cols * ideal_card_w + (cols - 1) * gap + frame))
popup_w=$(min "$ideal_popup_w" "$max_popup_w")
interior_w=$((popup_w - frame))

card_w=$ideal_card_w
needed_w=$((cols * ideal_card_w + (cols - 1) * gap))
if [ "$needed_w" -gt "$interior_w" ]; then
	card_w=$(((interior_w - (cols - 1) * gap) / cols))
	[ "$card_w" -lt 12 ] && card_w=12
	[ "$card_w" -gt 46 ] && card_w=46
fi
card_inner_w=$((card_w - 2))
[ "$card_inner_w" -lt 4 ] && card_inner_w=4

grid_w=$((cols * card_w + (cols - 1) * gap))
popup_w=$((grid_w + frame))
popup_w=$(min "$popup_w" "$max_popup_w")

if [ "$card_w" -eq "$ideal_card_w" ]; then
	preview_h=12
else
	preview_h=$((card_inner_w / 3))
	[ "$preview_h" -lt 3 ] && preview_h=3
fi

card_h=$((preview_h + 3))
grid_h=$((rows * card_h + (rows - 1) * gap))
popup_h=$((grid_h + frame))

max_popup_h=$((client_h - 2))
max_popup_h=$(max "$max_popup_h" 1)

min_popup_w=$(min 50 "$max_popup_w")
min_popup_h=$(min 8 "$max_popup_h")

popup_h=$(min "$popup_h" "$max_popup_h")
popup_w=$(max "$popup_w" "$min_popup_w")
popup_h=$(max "$popup_h" "$min_popup_h")

tmux display-popup -E -w "$popup_w" -h "$popup_h" \
	-b rounded -S "fg=#A0A0A0" \
	"/usr/bin/env TMUX_BIN='$TMUX_BIN' TMUX_TAB_COLOR='$TMUX_TAB_COLOR' TMUX_TAB_TEXT_COLOR='$TMUX_TAB_TEXT_COLOR' TMUX_TAB_MAX_TABS='$TMUX_TAB_MAX_TABS' '$BINARY'"
