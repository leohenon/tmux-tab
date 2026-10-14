#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/mru.sh"

client="$1"
if [ -n "$client" ]; then
	server_pid=$(tmux display-message -p '#{pid}')
	marker="/tmp/tmux-tab-preview-${server_pid}-${client##*/}"
	if [ -f "$marker" ]; then
		read -r owner <"$marker"
		case "$owner" in
		'' | *[!0-9]* | 0) ;;
		*)
			if kill -0 "$owner" 2>/dev/null; then
				exit 0
			fi
			;;
		esac
		rm -f "$marker"
	fi
fi

current_session="${2:-$(tmux display-message -p '#{session_name}' 2>/dev/null)}"

if [ -n "$current_session" ]; then
	mru_push "$current_session"
fi
