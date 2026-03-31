#!/usr/bin/env bash
set -eu

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"
BINARY="$PLUGIN_DIR/bin/switcher"
REPO="leohenon/tmux-tab"

log() {
	tmux display-message "tmux-tab: $1"
}

detect_target() {
	local os arch
	os=$(uname -s)
	arch=$(uname -m)

	case "$os" in
	Darwin) os="darwin" ;;
	Linux) os="linux" ;;
	*)
		log "unsupported OS: $os"
		return 1
		;;
	esac

	case "$arch" in
	x86_64 | amd64) arch="amd64" ;;
	aarch64 | arm64) arch="arm64" ;;
	*)
		log "unsupported architecture: $arch"
		return 1
		;;
	esac

	printf '%s-%s\n' "$os" "$arch"
}

download_binary() {
	local target url tmpfile
	target="$1"
	url="https://github.com/$REPO/releases/latest/download/switcher-$target"
	tmpfile="$BINARY.tmp"

	mkdir -p "$(dirname "$BINARY")"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$tmpfile" || return 1
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$tmpfile" "$url" || return 1
	else
		return 1
	fi

	chmod +x "$tmpfile"
	mv "$tmpfile" "$BINARY"
}

build_binary() {
	if ! command -v go >/dev/null 2>&1; then
		return 1
	fi

	mkdir -p "$(dirname "$BINARY")"
	(
		cd "$PLUGIN_DIR"
		go build -o "$BINARY" ./cmd/switcher/
	)
}

main() {
	if [ -x "$BINARY" ]; then
		exit 0
	fi

	log "installing switcher binary..."

	if target=$(detect_target) && download_binary "$target"; then
		log "installed prebuilt binary for $target"
		exit 0
	fi

	if build_binary; then
		log "built switcher locally with Go"
		exit 0
	fi

	log "install failed: no release binary and Go not available"
	exit 1
}

main "$@"
