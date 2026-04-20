#!/usr/bin/env bash
set -eu

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$CURRENT_DIR")"
BINARY="$PLUGIN_DIR/bin/switcher"
REF_FILE="$PLUGIN_DIR/bin/switcher.ref"
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

binary_source_dirty() {
	git -C "$PLUGIN_DIR" diff --quiet -- cmd/switcher go.mod go.sum || return 0
	git -C "$PLUGIN_DIR" diff --cached --quiet -- cmd/switcher go.mod go.sum || return 0

	if [ -n "$(git -C "$PLUGIN_DIR" ls-files --others --exclude-standard -- cmd/switcher go.mod go.sum 2>/dev/null)" ]; then
		return 0
	fi

	return 1
}

current_tag() {
	git -C "$PLUGIN_DIR" describe --tags --exact-match HEAD 2>/dev/null || true
}

binary_source_ref() {
	git -C "$PLUGIN_DIR" log -n1 --format=%H -- cmd/switcher go.mod go.sum
}

installed_ref() {
	[ -f "$REF_FILE" ] || return 1
	cat "$REF_FILE"
}

write_installed_ref() {
	local ref="$1"
	local tmpfile
	tmpfile="$REF_FILE.tmp"

	mkdir -p "$(dirname "$REF_FILE")"
	printf '%s\n' "$ref" >"$tmpfile"
	mv "$tmpfile" "$REF_FILE"
}

install_up_to_date() {
	local current installed

	[ -x "$BINARY" ] || return 1
	binary_source_dirty && return 1

	current=$(binary_source_ref) || return 1
	[ -n "$current" ] || return 1
	installed=$(installed_ref) || return 1
	[ "$current" = "$installed" ]
}

download_binary() {
	local target="$1"
	local tag="$2"
	local url tmpfile
	url="https://github.com/$REPO/releases/download/$tag/switcher-$target"
	tmpfile="$BINARY.tmp"

	mkdir -p "$(dirname "$BINARY")"
	rm -f "$tmpfile"

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
	local tmpfile
	tmpfile="$BINARY.tmp"

	if ! command -v go >/dev/null 2>&1; then
		return 1
	fi

	mkdir -p "$(dirname "$BINARY")"
	rm -f "$tmpfile"
	(
		cd "$PLUGIN_DIR"
		go build -o "$tmpfile" ./cmd/switcher/
	) || {
		rm -f "$tmpfile"
		return 1
	}

	chmod +x "$tmpfile"
	mv "$tmpfile" "$BINARY"
}

main() {
	local binary_ref=""
	local tag=""
	local dirty=0

	if install_up_to_date; then
		exit 0
	fi

	if binary_source_dirty; then
		dirty=1
	else
		binary_ref=$(binary_source_ref) || {
			log "install failed: could not determine switcher revision"
			exit 1
		}
		if [ -z "$binary_ref" ]; then
			log "install failed: could not determine switcher revision"
			exit 1
		fi
		tag=$(current_tag)
	fi

	log "installing switcher binary..."

	if [ -n "$tag" ]; then
		if target=$(detect_target) && download_binary "$target" "$tag"; then
			write_installed_ref "$binary_ref"
			log "installed prebuilt binary for $target"
			exit 0
		fi
	fi

	if build_binary; then
		if [ "$dirty" -eq 0 ]; then
			write_installed_ref "$binary_ref"
		else
			rm -f "$REF_FILE"
		fi
		log "built switcher locally with Go"
		exit 0
	fi

	if [ "$dirty" -eq 1 ]; then
		log "install failed: Go is required to build local switcher changes"
	elif [ -n "$tag" ]; then
		log "install failed: release binary unavailable and Go not available"
	else
		log "install failed: unreleased checkout requires Go to build switcher"
	fi

	exit 1
}

main "$@"
