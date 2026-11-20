# dotfiles-2

Personal Linux desktop configuration built around **Hyprland** and **Quickshell**. The repository contains a modular Quickshell shell, launcher, settings/control center, notification integration, scripts, and supporting configuration data.

## Overview

- `shell.qml` is the shell entry point. It creates the bar instances, launcher, settings window, and IPC handlers.
- `Bar.qml` and related components provide the panel and status indicators.
- `Launcher.qml` provides application/command search, hybrid file and image search, clipboard history, emoji selection, snippets, calculator and unit conversion, configurable bangs, and file OCR.
- `Settings.qml`, `Config.qml`, and `Theme.qml` provide settings and appearance controls.
- `popups/` and other QML components provide focused system controls.
- `scripts/` contains helper utilities used by the desktop.
- `docs/` contains feature-specific guides.

## Launcher

| Mode | Shortcut | Purpose |
| --- | --- | --- |
| All | `Alt+1` | Search apps, commands, file contents, snippets and web bangs |
| Files | `Alt+2` | Search filenames and indexed document/image content |
| Clipboard | `Alt+3` | Browse, preview, copy and paste cliphist entries |
| Emoji | `Alt+4` | Search and paste emoji |
| Snippets | `Alt+5` | Search and expand text templates |
| Hidden apps | Launcher action | View and unhide hidden desktop entries |

In All mode, `/`, `;`, `'`, and `,` switch to Files, Clipboard, Emoji, and Snippets. The launcher also supports shell execution with `>`, calculator expressions with `=`, and configurable `!` bangs.

Quickshell IPC:

```sh
quickshell ipc call launcher toggle all
quickshell ipc call launcher open files
quickshell ipc call launcher reindex
quickshell ipc call launcher reloadConfig
```

## Hydrogen integration

Hydrogen provides the local Rust backend for indexing, content search, visual retrieval and OCR. The launcher expects hydrogen on PATH.

- `hydrogen index sync` synchronises files and starts eligible image indexing.
- `hydrogen query QUERY --limit 25` performs lexical search.
- After enabling semantic indexing, the launcher adds `--semantic` to text queries. Hydrogen fuses lexical results with MiniLM document vectors and CLIP cross-modal image vectors.
- Image-file results expose **Find Visually Similar Images**, backed by `hydrogen query --image PATH --limit 25`.
- **Index Images (Rust OCR + Vision)** runs `hydrogen index sync-images`.

### Enable semantic and visual search

Semantic indexing is deliberately opt-in. In the launcher, choose **Build Semantic & Visual Index**. This runs:

```sh
HYDROGEN_EMBEDDINGS=1 hydrogen index sync
HYDROGEN_EMBEDDINGS=1 hydrogen index embed
```

This downloads the local MiniLM and CLIP models, backfills vectors for existing documents and images, and stores the enabled state in the launcher state file. It can use additional CPU and RAM during the initial backfill. Once enabled, future launcher syncs keep embeddings updated. Search inference remains local.

To disable semantic search and future embedding updates, choose **Disable Semantic & Visual Search** in the launcher. Existing vectors and downloaded model files are retained.

### OCR

The launcher uses Hydrogen's Rust-native OCR commands:

- **Extract Printed Text (Rust OCR)** runs `hydrogen ocr file PATH`.
- **Recognise Formula as LaTeX** runs `hydrogen ocr file PATH --math`.
- `Ctrl+O` runs printed-text OCR on the selected image file.
- Hydrogen copies and pastes the result into the previously focused window.

Clipboard images remain available for preview, copying and pasting. Clipboard-image OCR actions are intentionally not exposed. General handwritten prose does not yet have a dedicated handwriting model. See [Hydrogen model setup](https://github.com/oarabilekoore/hydrogen/blob/main/docs/MODELS.md) for supported formats and limitations.

## Index state and searchable roots

Hydrogen stores its state under `~/.local/state/quickshell-launcher` by default. Search roots include Documents, Downloads, Pictures, Videos, and Projects. The launcher caches filenames in `file-index.txt` and watches `index.rev` while open, refreshing its cache and active search after a completed sync.

## Notifications and OSD

The current shell configuration intentionally does not instantiate a Quickshell notification server or OSD. SwayNC owns desktop notifications, avoiding two applications competing for `org.freedesktop.Notifications`.

## Requirements

- Hyprland
- Quickshell and Qt Quick
- Hydrogen (launcher backend)
- SwayNC
- `cliphist`, `wl-copy`, and `wtype` for clipboard workflows
- `hyprctl` for Hyprland control
- `xdg-open` and standard desktop utilities

## Installation

This repository is a collection of desktop configuration files rather than a universal installer. Review the files and adapt paths and dependencies before deploying them.

The shell entry point is `shell.qml`. Quickshell should load the repository's shell entry point, with the repository's QML modules and supporting data kept together. Hydrogen must be installed and available on PATH.

## Configuration and data

- `Config.qml` defines defaults, persisted settings, and the settings-file path.
- User settings are stored at `~/.config/quickshell/settings.json`.
- Launcher bangs and snippets are loaded from the Quickshell configuration directory.
- Launcher state is stored at `~/.local/state/quickshell-launcher/state.json`.

Do not commit personal tokens, API keys, private paths, or machine-specific secrets.

## Documentation

- [Launcher guide](docs/LAUNCHER.md)
- [Bangs guide](docs/BANGS.md)
- [Notifications guide](docs/NOTIFICATIONS.md)

## Related project

[Hydrogen](https://github.com/oarabilekoore/hydrogen) provides the launcher's indexing, hybrid search and OCR commands. Model setup and supported OCR capabilities are documented in its repository.

## License

No license is currently declared in this repository. Until one is added, assume the source is not licensed for redistribution or reuse beyond the rights granted by GitHub's terms.