#!/usr/bin/env bash
set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCKET="${TMUX_TAB_TEST_SOCKET:-tmux-tab-stress-$$}"
RELOAD_ITERS="${TMUX_TAB_RELOAD_ITERS:-100}"
SWITCH_ITERS="${TMUX_TAB_SWITCH_ITERS:-1000}"
READER_ITERS="${TMUX_TAB_READER_ITERS:-5000}"
READER_ERR="${TMPDIR:-/tmp}/tmux-tab-stress-reader-$$.err"
WRAPPER_DIR="${TMPDIR:-/tmp}/tmux-tab-stress-bin-$$"
SESSIONS=(one two three)

cleanup() {
	tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
	rm -f "$READER_ERR"
	rm -rf "$WRAPPER_DIR"
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

tmux_cmd() {
	tmux -L "$SOCKET" "$@"
}

server_pid() {
	tmux_cmd display-message -p '#{pid}'
}

mru_file() {
	echo "/tmp/tmux-tab-mru-v2-$(server_pid)"
}

read_mru_lines() {
	local file
	file=$(mru_file)
	if [ ! -f "$file" ]; then
		return 0
	fi

	while IFS= read -r line; do
		[ -n "$line" ] && echo "$line"
	done <"$file"
}

setup_tmux_wrapper() {
	mkdir -p "$WRAPPER_DIR"
	cat >"$WRAPPER_DIR/tmux" <<EOF
#!/usr/bin/env bash
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOF
	chmod +x "$WRAPPER_DIR/tmux"
}

push_session() {
	local session="$1"
	PATH="$WRAPPER_DIR:$PATH" bash -lc "source '$CURRENT_DIR/mru.sh'; mru_push '$session'"
}

assert_unique_sessions() {
	local label="$1"
	shift
	local -A seen=()
	local entry
	for entry in "$@"; do
		if [ -n "${seen[$entry]+x}" ]; then
			fail "$label: duplicate session '$entry' in MRU"
		fi
		seen["$entry"]=1
	done
}

assert_mru_state() {
	local expected_head="$1"
	local expected_count="$2"
	local -a lines
	mapfile -t lines < <(read_mru_lines)

	if [ ${#lines[@]} -ne "$expected_count" ]; then
		fail "expected $expected_count MRU sessions, got ${#lines[@]} (${lines[*]-})"
	fi

	if [ "${lines[0]-}" != "$expected_head" ]; then
		fail "expected MRU head '$expected_head', got '${lines[0]-}'"
	fi

	assert_unique_sessions "mru state" "${lines[@]}"
}

seed_write_test() {
	local i
	echo "seed write test (${RELOAD_ITERS} iterations)"
	for i in $(seq 1 "$RELOAD_ITERS"); do
		rm -f "$(mru_file)"
		push_session one
		assert_mru_state one 1
	done
}

reader_loop() {
	local i
	for i in $(seq 1 "$READER_ITERS"); do
		local -a lines
		mapfile -t lines < <(read_mru_lines)

		if [ ${#lines[@]} -ne 3 ]; then
			echo "reader observed wrong MRU size: ${#lines[@]} (${lines[*]-})" >"$READER_ERR"
			return 1
		fi

		local -A seen=()
		local entry
		for entry in "${lines[@]}"; do
			if [ -n "${seen[$entry]+x}" ]; then
				echo "reader observed duplicate MRU session: ${lines[*]-}" >"$READER_ERR"
				return 1
			fi
			seen["$entry"]=1
		done
	done
}

switch_stress_test() {
	local i target
	echo "write stress test (${SWITCH_ITERS} pushes, ${READER_ITERS} reader iterations)"

	push_session two
	assert_mru_state two 2
	push_session three
	assert_mru_state three 3
	push_session one
	assert_mru_state one 3

	reader_loop &
	local reader_pid=$!

	for i in $(seq 1 "$SWITCH_ITERS"); do
		target="${SESSIONS[$((i % ${#SESSIONS[@]}))]}"
		push_session "$target"
		assert_mru_state "$target" 3
	done

	if ! wait "$reader_pid"; then
		fail "$(cat "$READER_ERR")"
	fi
}

echo "starting isolated tmux server on socket '$SOCKET'"
rm -f "$READER_ERR"
setup_tmux_wrapper
tmux_cmd new-session -d -s one
for session in two three; do
	tmux_cmd new-session -d -s "$session"
done

seed_write_test
switch_stress_test

echo "PASS: no MRU write race detected"
