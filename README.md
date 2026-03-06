# tmux-popup

A lightweight tmux plugin that opens auto-sized popups from a typed message.

## Requirements

- tmux 3.2 or newer (`display-popup` required)
- [TPM](https://github.com/tmux-plugins/tpm)

## Installation

Add the plugin to your tmux config:

```tmux
set -g @plugin 'tarik/tmux-popup'
```

Reload tmux config and install with TPM (`prefix + I`).

## Usage

Press `prefix + P`.

The plugin opens a prompt (`Popup message`). Type a message and press Enter.

Behavior:

- In `auto` mode, popup width and height are calculated from your message content.
- Inner padding is applied around the message.
- If needed, lines wrap automatically (soft-wrap on spaces, hard-wrap long words).
- Popup opens in the top-right corner with configurable margins.
- Popup style colors are inverted by default (based on tmux popup style fg/bg).
- Message animation mode is configurable (`typewriter` or `slide`).
- In `slide` mode, the message slides in from right, stays for 2 seconds, then slides out left and closes automatically.
- Popup opens at its full computed size from the beginning.
- Popup is borderless; `typewriter` mode stays open until dismissed (Esc or Ctrl-c).

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
set -g @tmux-popup-key 'P'          # Default: P
set -g @tmux-popup-size 'auto'      # auto|small|medium|large
set -g @tmux-popup-padding-x '2'    # Default: 2
set -g @tmux-popup-padding-y '1'    # Default: 1
set -g @tmux-popup-margin-right '2' # Default: 2
set -g @tmux-popup-margin-top '1'   # Default: 1
set -g @tmux-popup-invert-colors 'on' # Default: on
set -g @tmux-popup-animation-mode 'typewriter' # typewriter|slide
set -g @tmux-popup-type-delay '0.06' # Seconds per character
set -g @tmux-popup-style 'fg=colour252,bg=colour235' # Optional base style
```
