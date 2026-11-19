# Quickshell Launcher Guide

The launcher is the keyboard-driven application and workflow surface for this
Quickshell setup. It delegates file indexing, content search and OCR to the
Hydrogen command-line backend.

## Modes and shortcuts

| Mode | Shortcut | Sigil in All mode | Purpose |
| --- | --- | --- | --- |
| All | `Alt+1` | Default | Search applications, commands, files, snippets and configured bangs |
| Files | `Alt+2` | `/` | Search filenames and indexed document/image content |
| Clipboard | `Alt+3` | `;` | Browse `cliphist` history, preview entries and run OCR on images |
| Emoji | `Alt+4` | `'` | Search and paste emoji |
| Snippets | `Alt+5` | `,` | Search and expand text templates |
| Hidden apps | Launcher action | — | View and unhide hidden desktop entries |

Use `Tab` and `Shift+Tab` to cycle modes. The first character sigils only
switch modes when typed at the beginning of an All-mode query.

Other All-mode prefixes:

- `>` runs a shell command. `Enter` runs it detached; `Ctrl+Enter` opens it
  in Ghostty.
- `=` forces calculator evaluation. Basic arithmetic, common functions,
  constants and supported unit conversions are available.
- `!` invokes a configured bang.

## IPC

The shell exposes these launcher commands:

```sh
quickshell ipc call launcher toggle all
quickshell ipc call launcher open files
quickshell ipc call launcher close
quickshell ipc call launcher reindex
quickshell ipc call launcher reloadConfig
```

A dmenu-compatible caller can pass a prompt, input file and output file:

```sh
quickshell ipc call launcher dmenu "Select an item" /tmp/options.txt /tmp/selection.txt
```

## Hydrogen integration

Hydrogen is expected to be available on `PATH`. The launcher uses:

- `hydrogen index sync` to synchronise the index.
- `hydrogen query QUERY --limit 25` to retrieve content-search results.
- `hydrogen index sync-images` for the explicit image-index action.
- Hydrogen's OCR commands for clipboard and file image recognition.

The launcher caches the filename list in
`~/.local/state/quickshell-launcher/file-index.txt`. It watches Hydrogen's
`index.rev` revision marker while the launcher is open, so a completed index
sync invalidates the local cache and refreshes active file searches. This is a
cache refresh mechanism, not a replacement for Hydrogen's filesystem watcher.

The actual searchable roots and index state directory are configured by
Hydrogen, not by this QML file. Check the Hydrogen configuration and CLI help
when changing those settings.

## OCR

- In Clipboard mode, select an image and press `Ctrl+O`.
- In Files mode, use the image action labelled **OCR to Markdown**.
- The result is copied as text and pasted into the previously focused window.

The available OCR engines and model installation steps are maintained by
Hydrogen. See the [Hydrogen OCR documentation](https://github.com/oarabilekoore/hydrogen#ocr-runtime)
rather than installing a second OCR stack from this repository.

## User configuration

The launcher reads:

- `~/.config/quickshell/bangs.json`
- `~/.config/quickshell/snippets.json`
- `~/.local/state/quickshell-launcher/state.json`

Bundled bang defaults are copied into the user configuration directory on
first launch. Keep personal snippets and machine-specific settings out of
version control.
