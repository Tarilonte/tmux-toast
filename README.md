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

- Popup width and height are calculated from your message content.
- Inner padding is applied around the message.
- If needed, lines wrap automatically (soft-wrap on spaces, hard-wrap long words).
- The popup stays open until dismissed, with `[ESC]` shown on the top-right border.

## Escapes

Inside the prompt input:

- `\n` creates a newline.
- `\\n` stays as literal `\n` text.

## Options

```tmux
set -g @tmux-popup-key 'P'          # Default: P
set -g @tmux-popup-padding-x '2'    # Default: 2
set -g @tmux-popup-padding-y '1'    # Default: 1
```
