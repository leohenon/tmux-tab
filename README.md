<h1 align="center">tmux-tab</h1>

<p align="center">
  <a href="https://github.com/leohenon/tmux-tab/releases/latest"><img src="https://img.shields.io/github/v/release/leohenon/tmux-tab?style=flat-square&logo=github&logoColor=white&label=Release&color=3fb950" alt="Release"></a>
  <a href="https://github.com/tmux/tmux"><img src="https://img.shields.io/badge/tmux-3.2%2B-85c1e9?style=flat-square&logo=tmux&logoColor=white" alt="tmux"></a>
</p>

<p align="center">
  Alt-tab for tmux sessions.
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

| Key                                     | Action                           |
| --------------------------------------- | -------------------------------- |
| `prefix + Tab`                          | Open switcher                    |
| `Tab` / `l` / `j` / `Right` / `Down`    | Next session in the switcher     |
| `Shift-Tab` / `h` / `k` / `Left` / `Up` | Previous session in the switcher |
| `Enter`                                 | Switch to selected session       |
| `Esc` / `q`                             | Close                            |

## Options

```tmux
# Popup
set -g @tmux-tab-bind 'Tab'
set -g @tmux-tab-prefix 'on'
set -g @tmux-tab-color '#cba6f7'
set -g @tmux-tab-text-color '#000000'
set -g @tmux-tab-max-tabs '7'

# Optional direct cycle keys
set -g @tmux-tab-cycle-bind 'n'
set -g @tmux-tab-cycle-prev-bind 'p'
set -g @tmux-tab-cycle-prefix 'on'
set -g @tmux-tab-cycle-timeout '2'

# Optional history reset
set -g @tmux-tab-reset-on-detach 'off'
```

> [!NOTE]
>
> - `@tmux-tab-bind` sets the picker trigger key.
> - `@tmux-tab-prefix` controls whether the picker trigger requires tmux prefix.
> - `@tmux-tab-color` controls the selected card highlight color.
> - `@tmux-tab-text-color` controls the selected card label text color.
> - `@tmux-tab-max-tabs` sets the maximum number of visible cards. Supported range: `5` to `12`.
> - `@tmux-tab-cycle-bind` sets the optional next-session key. Set it to an empty string to disable it.
> - `@tmux-tab-cycle-prev-bind` sets the optional previous-session key.
> - `@tmux-tab-cycle-prefix` controls whether the optional cycle keys require tmux prefix.
> - `@tmux-tab-cycle-timeout` keeps repeated cycle presses in the same sequence for `n` seconds.
> - `@tmux-tab-reset-on-detach` clears MRU history when the last tmux client detaches from the server.

## How It Works

- tmux hooks keep a per-server MRU list in `/tmp` for the picker. Newly created but never visited sessions are excluded.
- Previews come from `tmux capture-pane -e` and refresh while the popup is open.
- Optional direct cycle keys switch sessions immediately without opening the picker.
- They cycle through a short-lived snapshot of the MRU order, so repeated presses keep moving forward or backward instead of bouncing between the last two sessions.
- After the cycle timeout expires, a new snapshot is taken.

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
