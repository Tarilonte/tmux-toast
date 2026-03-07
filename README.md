# tmux-toast

A lightweight tmux plugin that opens auto-sized popups from a typed message.

## Requirements

- tmux 3.2 or newer (`display-popup` required)
- [TPM](https://github.com/tmux-plugins/tpm)

## Installation

Add the plugin to your tmux config:

```tmux
set -g @plugin 'tarik/tmux-toast'
```

Reload tmux config and install with TPM (`prefix + I`).

## Usage

Press `prefix + P`.

The plugin opens a prompt (`Toast message`). Type a message and press Enter.

Behavior:

- In `auto` mode, popup width and height are calculated from your message content.
- Inner padding is applied around the message.
- If needed, lines wrap automatically (soft-wrap on spaces, hard-wrap long words).
- Toast opens in the top-right corner with configurable margins.
- Popup colors are derived from tmux styles (`popup-style` -> `window-active-style` -> `window-style` -> `status-style`).
- `@tmux-toast-style='invert'` (default) swaps fg/bg and keeps a borderless toast.
- `@tmux-toast-style='normal'` keeps normal fg/bg and shows a rounded border.
- Backend is configurable (`popup` or `tty`) with `popup` as default.
- `tty` backend does not capture keys, but heavy pane output may cause visual overlap.
- Message animation mode is configurable (`typewriter` or `slide`).
- In `slide` mode, the message slides in from right, stays for `@tmux-toast_duration` seconds, then slides out left and closes automatically.
- In `typewriter` mode, the message writes in, stays for `@tmux-toast_duration` seconds, then writes out and closes automatically.
- Toast opens at its full computed size from the beginning.
- Invert style is borderless; normal style uses rounded corners.

## Size Presets

You can pick a preconfigured popup size:

- `auto` (default): content-based sizing (current behavior)
- `small`: `45% x 30%`
- `medium`: `65% x 50%`
- `large`: `85% x 70%`

## Escapes

Inside the prompt input:

- `\n` creates a newline.
- `\\n` stays as literal `\n` text.

## Text Formatting (Markdown)

The popup supports lightweight markdown-style formatting:

- `**bold**`
- `*italic*`
- `__underline__`

Notes:

- Underline uses `__...__` (extension, not standard CommonMark).
- Use backslash to keep markers literal: `\*`, `\_`, `\\`.

## Options

```tmux
set -g @tmux-toast-key 'P'          # Default: P
set -g @tmux-toast-size 'auto'      # auto|small|medium|large
set -g @tmux-toast-padding-x '2'    # Default: 2
set -g @tmux-toast-padding-y '1'    # Default: 1
set -g @tmux-toast-margin-right '2' # Default: 2
set -g @tmux-toast-margin-top '1'   # Default: 1
set -g @tmux-toast-style 'invert'    # invert|normal (Default: invert)
set -g @tmux-toast-backend 'popup'   # popup|tty (Default: popup)
set -g @tmux-toast-animation-mode 'typewriter' # typewriter|slide
set -g @tmux-toast-type-delay '0.06' # Seconds per character
set -g @tmux-toast_duration '5'      # Seconds before write-out/slide-out
```
