# Quickshell Launcher Guide

The launcher is the keyboard-driven application and workflow surface for this Quickshell setup. It delegates indexing, lexical/semantic content search, visual image retrieval and Rust-native OCR to Hydrogen.

## Modes and shortcuts

| Mode | Shortcut | Sigil in All mode | Purpose |
| --- | --- | --- | --- |
| All | `Alt+1` | Default | Search apps, commands, files, snippets and configured bangs |
| Files | `Alt+2` | `/` | Search filenames and indexed document/image content |
| Clipboard | `Alt+3` | `;` | Browse, preview, copy and paste cliphist history |
| Emoji | `Alt+4` | `'` | Search and paste emoji |
| Snippets | `Alt+5` | `,` | Search and expand text templates |
| Hidden apps | Launcher action | — | View and unhide hidden desktop entries |

Use Tab and Shift+Tab to cycle modes. The first-character sigils switch modes only when typed at the beginning of an All-mode query.

Other All-mode prefixes:

- `>` runs a shell command. Enter runs it detached; Ctrl+Enter opens it in Ghostty.
- `=` forces calculator evaluation.
- `!` invokes a configured bang.

## IPC

```sh
quickshell ipc call launcher toggle all
quickshell ipc call launcher open files
quickshell ipc call launcher close
quickshell ipc call launcher reindex
quickshell ipc call launcher reloadConfig
```

## Hydrogen integration

The launcher uses Hydrogen as the single source of truth for roots, indexing policy, search limits and local RAG model settings. It does not pass model names, RAG limits or semantic-indexing environment overrides.

- `hydrogen index sync` to synchronise files and start eligible image indexing.
- `hydrogen query QUERY` (uses the configured default result limit) for lexical content search.
- `hydrogen query QUERY` also uses semantic retrieval automatically when `indexing.embeddings_enabled` is true. This combines lexical, MiniLM document-vector and CLIP cross-modal retrieval.
- `hydrogen query --image PATH` (uses the configured default result limit) for image-to-image retrieval. The launcher exposes this as **Find Visually Similar Images** on image-file results.
- `hydrogen index sync-images` for explicit Rust OCR/image indexing.
- `hydrogen ocr file PATH` for printed text and `hydrogen ocr file PATH --math` for formula-to-LaTeX recognition.

### Enable semantic and visual indexing

Semantic indexing is opt-in. Choose **Build Semantic & Visual Index** from the launcher command list. It runs:

```sh
hydrogen config set indexing.embeddings_enabled true
hydrogen index sync
hydrogen index embed
```

The first run downloads MiniLM and CLIP model files and backfills vectors for already indexed documents and images. This initial step can use additional CPU and RAM. Hydrogen stores the enabled state in `~/.config/hydrogen/config.toml`; future syncs automatically maintain vectors without launcher-managed environment variables. Text queries automatically use semantic retrieval while it is enabled; image actions use the CLIP image encoder.

To disable semantic queries and future embedding updates, choose **Disable Semantic & Visual Search** in the launcher. This changes Hydrogen configuration. Existing vector rows and downloaded model files are not deleted.

### Index and cache refresh

The launcher caches the filename list in `~/.local/state/quickshell-launcher/file-index.txt`. It watches Hydrogen's `index.rev` revision marker while the launcher is open, so a completed index sync invalidates the local cache and refreshes active file searches. This is a cache refresh mechanism, not a replacement for Hydrogen's filesystem watcher.

## OCR

- In Files mode, choose **Extract Printed Text (Rust OCR)** for printed content.
- Choose **Recognise Formula as LaTeX** for mathematical formula crops.
- `Ctrl+O` runs the printed-text action on the selected image file.
- Hydrogen copies and pastes the result into the previously focused window.
- Clipboard images can still be previewed, copied and pasted, but OCR is intentionally not offered in Clipboard mode.

Hydrogen uses Rust-native PP-OCRv6 Tiny for printed text and Texo for formula recognition. Dedicated handwritten-prose OCR is not yet wired. Model setup and support boundaries are documented in [Hydrogen model setup](https://github.com/oarabilekoore/hydrogen/blob/main/docs/MODELS.md).

## Open at match and previews

Content hits from Hydrogen carry the matching `page` (PDFs) or `line` (plain-text and code files). Enter opens the file at that spot, Ctrl+Enter still shows it in the folder. The preview pane shows the matching PDF page, or the lines around the matching line (marked with `▶`).

Override the commands at the top of `Launcher.qml` if needed. Placeholders are `{file}`, `{page}`, `{line}` and `{find}`:

```qml
property var pdfViewerCmd: ["zathura", "-P", "{page}", "-f", "{find}", "{file}"]
property var editorCmd: ["nvim", "+{line}", "{file}"]
property bool editorInTerminal: true
```

With `pdfViewerCmd` empty the launcher tries zathura, okular, evince and mupdf, then falls back to `xdg-open`.

## User configuration

The launcher reads:

- `~/.config/quickshell/bangs.json`
- `~/.config/quickshell/snippets.json`
- `~/.local/state/quickshell-launcher/state.json`

Bundled bang defaults are copied into the user configuration directory on first launch. Keep personal snippets and machine-specific settings out of version control.

### Unified Hydrogen knowledge and local RAG

In Files mode and All mode, the launcher calls `hydrogen search QUERY`. Hydrogen combines indexed files and PDF passages with saved answers, conversations and captured web articles. Selecting a saved answer or conversation opens its persistent conversation in the Hydrogen frontend; selecting a saved article opens its offline reading view. File results retain their existing page/line-aware open and preview behaviour.

AI generation is strictly on demand. The launcher adds an **Ask AI about this search** action, but does not run inference while you type. Selecting it opens the persistent Hydrogen frontend, creates a conversation and starts source-grounded generation there. The answer and citations are saved and become searchable in subsequent launcher searches.

Requirements: the configured local Ollama service and `[answer].model` must be available for generation. Search and previously saved knowledge remain usable without loading an AI model. Retrieval limits, endpoint, context size and generation parameters come from Hydrogen configuration. See [Hydrogen configuration](https://github.com/oarabilekoore/hydrogen/blob/main/docs/CONFIGURATION.md) and [Hydrogen RAG documentation](https://github.com/oarabilekoore/hydrogen/blob/main/docs/RAG.md).
