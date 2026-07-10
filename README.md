# ClipHistory

Smart clipboard manager for macOS — like Windows Win+V, but better.

## Features

- **Cmd+Shift+V** — global hotkey, opens near cursor
- **Auto-paste** — click item, it copies + pastes into previous app
- **Source tracking** — shows which app each clip came from
- **Auto-projects** — groups clips by source app (Dev, Web, Design, etc.)
- **Sensitive detection** — highlights passwords, tokens, credit cards
- **Sequential paste queue** — select multiple items, paste one by one
- **Pins** — keep important clips pinned
- **Auto-updates** — checks GitHub releases for new versions
- **Launch at login** — start with macOS
- **100% local** — no data leaves your Mac

## Install

### Build from source

```bash
git clone https://github.com/earflow/ClipHistory.git
cd ClipHistory
chmod +x build.sh
./build.sh
open ClipHistory.app
```

### Or download release

Download `ClipHistory.app.zip` from [Releases](https://github.com/earflow/ClipHistory/releases/latest), unzip and run.

### Install to Applications

```bash
cp -r ClipHistory.app /Applications/
```

## Permissions

ClipHistory needs two permissions:

1. **Accessibility** — for auto-paste into other apps
   - System Settings → Privacy & Security → Accessibility → Add ClipHistory

2. **That's it** — no network, no telemetry, fully local

## Uninstall

```bash
rm -rf /Applications/ClipHistory.app
rm -rf ~/Library/Application\ Support/ClipHistory
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+V | Toggle clipboard window |

## License

MIT
