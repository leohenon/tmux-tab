#!/usr/bin/env bash
mru_file() {
	local server_pid
	server_pid=$(tmux display-message -p '#{pid}')
	echo "/tmp/tmux-tab-mru-v2-${server_pid}"
}

mru_read() {
	local file
	file=$(mru_file)

	local current_session
	current_session=$(tmux display-message -p '#{session_name}' 2>/dev/null)

	local -a live_sessions
	while IFS= read -r s; do
		live_sessions+=("$s")
	done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)

	if [ ${#live_sessions[@]} -eq 0 ]; then
		return
	fi

	local -A live_set
	for s in "${live_sessions[@]}"; do
		live_set["$s"]=1
	done

	local -a mru_list
	local -A seen

	if [ -n "$current_session" ] && [ -n "${live_set[$current_session]+x}" ]; then
		mru_list+=("$current_session")
		seen["$current_session"]=1
	fi

	if [ -f "$file" ]; then
		while IFS= read -r name; do
			[ -z "$name" ] && continue
			if [ -n "${live_set[$name]+x}" ] && [ -z "${seen[$name]+x}" ]; then
				mru_list+=("$name")
				seen["$name"]=1
			fi
		done <"$file"
	fi

	for s in "${mru_list[@]}"; do
		echo "$s"
	done
}

mru_push() {
	local name="$1"
	local file tmpfile
	file=$(mru_file)
	tmpfile="${file}.tmp.$$"

	[ -z "$name" ] && return

	local -a entries
	if [ -f "$file" ]; then
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			[ "$line" = "$name" ] && continue
			entries+=("$line")
		done <"$file"
	fi

	{
		echo "$name"
		for e in "${entries[@]}"; do
			echo "$e"
		done
	} >"$tmpfile"

	mv "$tmpfile" "$file"
}
