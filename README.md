<h1 align="center">tmux-tab</h1>

<p align="center">
  <a href="https://github.com/leohenon/tmux-tab/actions/workflows/release.yml"><img src="https://img.shields.io/github/actions/workflow/status/leohenon/tmux-tab/release.yml?style=flat-square&logo=github&logoColor=white&label=Release&color=3fb950" alt="Release"></a>
  <a href="https://github.com/tmux/tmux"><img src="https://img.shields.io/badge/tmux-3.2%2B-85c1e9?style=flat-square&logo=tmux&logoColor=white" alt="tmux"></a>
</p>

<p align="center">
  alt-tab for tmux sessions.
</p>

![demo](assets/demo.gif)

## Install (TPM)

In your `tmux.conf`

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'leohenon/tmux-tab'

run '~/.tmux/plugins/tpm/tpm'
```

Reload tmux and press `prefix + I` to install plugins.

> [!NOTE]
>
> `tmux-tab` installs a prebuilt switcher binary automatically on first load. If no release binary is available, it falls back to building locally when Go is installed.

## Install (Manual)

```bash
git clone https://github.com/leohenon/tmux-tab ~/.tmux/plugins/tmux-tab
```

Add to your `tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-tab/tmux-tab.tmux
```

Reload with `tmux source-file ~/.tmux.conf`.

## Usage

| Key | Action |
| --- | --- |
| `Ctrl-Tab` | Open switcher |
| `Tab` / `l` / `j` / `Right` / `Down` | Next session |
| `Shift-Tab` / `h` / `k` / `Left` / `Up` | Previous session |
| `Enter` | Switch to selected session |
| `Esc` / `q` | Close |

## Options

```tmux
set -g @tmux-tab-bind 'C-Tab'
set -g @tmux-tab-prefix 'off'
set -g @tmux-tab-color '#cba6f7'
set -g @tmux-tab-text-color '#000000'
```

> [!NOTE]
>
> - `@tmux-tab-bind` sets the trigger key.
> - `@tmux-tab-prefix` controls whether the trigger requires tmux prefix.
> - `@tmux-tab-color` controls the selected card highlight color.
> - `@tmux-tab-text-color` controls the selected card label text color.

## How It Works

- tmux hooks keep a per-server MRU session list in `/tmp`.
- Previews come from `tmux capture-pane -e` and refresh while the popup is open.

## Development

For local development, build the switcher manually:

```bash
go build -o bin/switcher ./cmd/switcher/
```

If you need to install the binary manually:

```bash
~/.tmux/plugins/tmux-tab/scripts/install.sh
```

## Requirements

- tmux 3.2+

## License

[MIT](LICENSE)
