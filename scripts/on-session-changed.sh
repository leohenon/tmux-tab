#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/mru.sh"

current_session=$(tmux display-message -p '#{session_name}' 2>/dev/null)

if [ -n "$current_session" ]; then
	mru_push "$current_session"
fi
