# tmux-toast

[![GitHub Release](https://img.shields.io/github/v/release/Tarilonte/tmux-toast)](https://github.com/Tarilonte/tmux-toast/releases)

TTY-native toast notifications for tmux with stacked rendering, markdown formatting, and scriptable CLI overrides.

![tmux-toast typewriter demo](assets/tmux-toast-typewriter.gif)

## Requirements

- tmux 3.2 or newer
- [TPM](https://github.com/tmux-plugins/tpm)

## Installation

Add the plugin to your tmux config:

```tmux
set -g @plugin 'Tarilonte/tmux-toast'
```

Reload tmux config and install with TPM (`prefix + I`).

## Quick Start

- Press `prefix + P`
- Type a message in the `Toast message` prompt
- Press Enter

## Usage

The default keybinding opens the `Toast message` prompt and renders the toast in the active tmux client.

You can also call the script directly:

```bash
~/.tmux/plugins/tmux-toast/scripts/toast.sh "Build finished"
```

From another script, the recommended invocation is:

```bash
tmux run-shell -b "~/.tmux/plugins/tmux-toast/scripts/toast.sh --message 'Build finished'"
```

Notes:

- The toast renderer needs an active tmux client.
- Calling it through `tmux run-shell -b` is the safest way to trigger a toast from automation.

CLI flags override tmux options for that single toast invocation.

```bash
~/.tmux/plugins/tmux-toast/scripts/toast.sh \
  --style normal \
  --animation none \
  --duration 2 \
  --delay 0.03 \
  --message "Deploy completed"
```

Supported script flags:

- `-m, --message <text>`
- `--style <invert|normal>`
- `--animation <none|typewriter|slide|toast-slide>`
- `--duration <seconds>`
- `--delay <seconds>`
- `--size <auto|small|medium|large>`
- `--padding-x <int>`
- `--padding-y <int>`
- `--margin-right <int>`
- `--margin-top <int>`
- `-h, --help`

Behavior:

- In `auto` mode, toast width and height are calculated from your message content.
- Inner padding is applied around the message.
- If needed, lines wrap automatically (soft-wrap on spaces, hard-wrap long words).
- Toasts are rendered in a top-right container anchored by `@tmux-toast-margin-top` and `@tmux-toast-margin-right`.
- If multiple toasts are active, new toasts are stacked below existing ones.
- If there is no room left in the container, new toasts are skipped.
- Colors are derived from tmux styles (`popup-style` -> `window-active-style` -> `window-style` -> `status-style`).
- `@tmux-toast-style='invert'` (default) swaps fg/bg and keeps a borderless toast.
- `@tmux-toast-style='normal'` keeps normal fg/bg and shows a rounded border.
- Toast rendering is non-blocking, so typing and scrolling continue while toasts are active.
- Message animation mode is configurable (`none`, `typewriter`, `slide`, or `toast-slide`).
- In `none` mode, the toast appears immediately with no entry/exit animation.
- In `slide` mode, the message slides in from right, stays for `@tmux-toast_duration` seconds, then slides out left and closes automatically.
- In `typewriter` mode, the message writes in, stays for `@tmux-toast_duration` seconds, then writes out and closes automatically.
- In `toast-slide` mode, the full toast frame slides in from offscreen right, stays for `@tmux-toast_duration` seconds, then slides out to the right.
- In `toast-slide` mode, frame delay is clamped to `0.01s` minimum to reduce rendering artifacts.
- `@tmux-toast-type-delay` is ignored when `@tmux-toast-animation-mode` is `none`.
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
set -g @tmux-toast-margin-right '2' # Default: 2
set -g @tmux-toast-margin-top '1'   # Default: 1
set -g @tmux-toast-style 'invert'    # invert|normal (Default: invert)
set -g @tmux-toast-animation-mode 'typewriter' # none|typewriter|slide|toast-slide
set -g @tmux-toast-type-delay '0.06' # Seconds per character
set -g @tmux-toast_duration '5'      # Seconds the toast remains visible
```

## Credits

Built with AI assistance in OpenCode, primarily using GPT-5.3 Codex.

## Demo Generation

Regenerate the README animation locally:

```bash
demo/setup_demo_tools.sh
demo/render_typewriter_demo_gif.sh
```

This writes:

- `assets/tmux-toast-typewriter.gif`
- `demo/tmux-toast-typewriter.cast`
