# tmux-toast

A lightweight tmux plugin that renders auto-sized terminal toasts from a typed message.

## Requirements

- tmux 3.2 or newer
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

- In `auto` mode, toast width and height are calculated from your message content.
- Inner padding is applied around the message.
- If needed, lines wrap automatically (soft-wrap on spaces, hard-wrap long words).
- Toasts are rendered in a top-center container anchored by `@tmux-toast-margin-top`.
- If multiple toasts are active, new toasts are stacked below existing ones.
- If there is no room left in the container, new toasts are skipped.
- Colors are derived from tmux styles (`popup-style` -> `window-active-style` -> `window-style` -> `status-style`).
- `@tmux-toast-style='invert'` (default) swaps fg/bg and keeps a borderless toast.
- `@tmux-toast-style='normal'` keeps normal fg/bg and shows a rounded border.
- Toast rendering is non-blocking, so typing and scrolling continue while toasts are active.
- Message animation mode is configurable (`typewriter` or `slide`).
- In `slide` mode, the message slides in from right, stays for `@tmux-toast_duration` seconds, then slides out left and closes automatically.
- In `typewriter` mode, the message writes in, stays for `@tmux-toast_duration` seconds, then writes out and closes automatically.
- Each toast opens at its full computed size from the beginning.
- Invert style is borderless; normal style uses rounded corners.

## Size Presets

You can pick a preconfigured toast size:

- `auto` (default): content-based sizing (current behavior)
- `small`: `45% x 30%`
- `medium`: `65% x 50%`
- `large`: `85% x 70%`

## Escapes

Inside the prompt input:

- `\n` creates a newline.
- `\\n` stays as literal `\n` text.

## Text Formatting (Markdown)

The toast supports lightweight markdown-style formatting:

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
set -g @tmux-toast-margin-top '1'   # Default: 1
set -g @tmux-toast-style 'invert'    # invert|normal (Default: invert)
set -g @tmux-toast-animation-mode 'typewriter' # typewriter|slide
set -g @tmux-toast-type-delay '0.06' # Seconds per character
set -g @tmux-toast_duration '5'      # Seconds before write-out/slide-out
```
