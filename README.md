# dotfiles-2

Personal Linux desktop configuration built around **Hyprland** and **Quickshell**. The repository contains a modular Quickshell shell, launcher, settings/control center, notification integration, scripts, and supporting configuration data.

## Overview

The Quickshell interface is organised around a small set of top-level QML components:

- `shell.qml` is the shell entry point. It creates the bar instances, launcher, settings window, and IPC handlers.
- `Bar.qml` and the related components provide the panel and status indicators.
- `Launcher.qml` provides application/command search, file search, clipboard history, emoji selection, snippets, calculator and unit conversion, configurable bangs, and OCR actions.
- `Settings.qml`, `Config.qml`, and `Theme.qml` provide the settings and appearance system, including per-module bar visibility controls.
- `popups/` and other QML components provide focused system controls.
- `scripts/` contains helper utilities used by the desktop.
- `docs/` contains feature-specific guides.

## Main features

### Launcher

The launcher supports several modes:

| Mode | Shortcut | Purpose |
| --- | --- | --- |
| All | `Alt+1` | Search apps, commands, files, snippets, and web bangs |
| Files | `Alt+2` | Search filenames and indexed document/image content |
| Clipboard | `Alt+3` | Browse `cliphist` history, preview entries, and OCR images |
| Emoji | `Alt+4` | Search and paste emoji |
| Snippets | `Alt+5` | Search and expand text templates |
| Hidden apps | Launcher action | View and unhide hidden desktop entries |

In All mode, the first-character sigils switch directly to a mode: `/` for Files, `;` for Clipboard, `'` for Emoji, and `,` for Snippets. The launcher also supports shell execution with `>`, calculator expressions with `=`, and configurable `!` bangs.

The launcher can be controlled over Quickshell IPC:

```sh
quickshell ipc call launcher toggle all
quickshell ipc call launcher open files
quickshell ipc call launcher reindex
quickshell ipc call launcher reloadConfig
```

### OCR

The launcher delegates OCR to the Hydrogen backend:

- Press `Ctrl+O` on an image in Clipboard mode to recognise a clipboard image.
- Use the image action **OCR to Markdown** in Files mode to recognise an image file.
- The result is copied as plain-text Markdown and can be pasted into the previously focused window.

Hydrogen now provides three on-demand OCR engines: Pix2Text for mixed text and mathematical formulas (with LaTeX output), TrOCR Small Handwritten for handwritten English lines, and RapidOCR as a legacy fallback. The default launcher action uses Pix2Text. To run handwriting recognition explicitly, use `hydrogen ocr file /path/to/note.png --engine handwriting` or `hydrogen ocr clip CLIPHIST_ID --engine handwriting`. Install the interactive models once from the Hydrogen checkout with `make install && make ocr-deps`. Model weights are downloaded on first use and cached locally. See the [Hydrogen OCR guide](https://github.com/oarabilekoore/hydrogen#ocr-runtime).

### File and image search

The launcher calls Hydrogen for content search and index maintenance. The backend maintains its state under `~/.local/state/quickshell-launcher` by default. The searchable roots include Documents, Downloads, Pictures, Videos, and Projects.

### Notifications and OSD

The current shell configuration intentionally does not instantiate a Quickshell notification server or OSD. SwayNC owns desktop notifications, avoiding two applications competing for `org.freedesktop.Notifications`.

## Requirements

This configuration is intended for a Linux Wayland desktop. The exact package set depends on which features are enabled, but the repository currently integrates with:

- Hyprland
- Quickshell and Qt Quick
- Hydrogen (launcher backend)
- SwayNC
- `cliphist`, `wl-copy`, and `wtype` for clipboard workflows
- `hyprctl` for Hyprland control
- `xdg-open` and standard desktop utilities

Additional commands and integrations are invoked by individual settings, launcher actions, and scripts.

## Installation

This repository is a collection of desktop configuration files rather than a universal installer. Review the files and adapt paths and dependencies to your system before deploying them.

The shell entry point is `shell.qml`. Quickshell should be configured to load the repository's shell entry point, with the repository's QML modules and supporting data kept together.

Hydrogen must be installed and available on `PATH` for launcher indexing, content search, and OCR actions to work.

## Configuration and data

- `Config.qml` defines defaults, persisted settings, and the settings-file path.
- User settings are stored at `~/.config/quickshell/settings.json`.
- Launcher bangs and snippets are loaded from the Quickshell configuration directory.
- `docs/` contains focused documentation for launcher, bangs, and notifications.

Do not commit personal tokens, API keys, private paths, or machine-specific secrets to this repository.

## Documentation

- [Launcher guide](docs/LAUNCHER.md)
- [Bangs guide](docs/BANGS.md)
- [Notifications guide](docs/NOTIFICATIONS.md)

## Related project

[Hydrogen](https://github.com/oarabilekoore/hydrogen) provides the launcher’s indexing, content-search and OCR commands. Its model/runtime requirements and supported operations are documented in the Hydrogen repository.

## License

No license is currently declared in this repository. Until one is added, assume the source is not licensed for redistribution or reuse beyond the rights granted by GitHub's terms.
