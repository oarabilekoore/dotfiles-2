# Quickshell Launcher Guide

A keyboard-driven Wayland launcher built with Quickshell (`~/.config/quickshell/Launcher.qml`), featuring hybrid Vector + SQLite FTS5 file content search, rich file previews, clipboard OCR, dynamic snippets, configurable `!bangs`, and a universal `dmenu` IPC interface.

---

## 1. Modes & Prefix Sigils

Type a sigil as the **first character** in `All` mode to switch directly into that mode, press `Tab` / `Shift+Tab` to cycle modes, or jump via `Alt+1`–`Alt+5`.

| Mode | Sigil | Shortcut | IPC Command | Purpose |
| :--- | :---: | :---: | :--- | :--- |
| **All** | *(default)* | `Alt+1` | `quickshell ipc call launcher toggle all` | Unified search across apps, commands, vector/FTS5 file contents, filenames, snippets, calculator, units, and web |
| **Files** | `/` | `Alt+2` | `quickshell ipc call launcher toggle files` | Hybrid Vector + FTS5 content search + filename search across `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Videos`, `~/Projects` |
| **Clipboard** | `;` | `Alt+3` | `quickshell ipc call launcher toggle clipboard` | `cliphist` history with image/text preview, single-entry delete (`Del`), full wipe (`Ctrl+D`), and image OCR (`Ctrl+O`) |
| **Emoji** | `'` | `Alt+4` | `quickshell ipc call launcher toggle emoji` | Grid emoji picker with recency boost and automatic paste-back into the previous window |
| **Snippets** | `,` | `Alt+5` | `quickshell ipc call launcher toggle snippets` | Dynamic text templates from `~/.config/quickshell/snippets.json` |
| **Hidden Apps** | — | — | `quickshell ipc call launcher toggle hidden` | View and unhide desktop entries hidden with `Ctrl+B` |
| **Shell Run** | `>` | — | — | Execute an arbitrary shell command (`Enter` background, `Ctrl+Enter` in `ghostty`) |
| **Calculator** | `=` | — | — | Force math evaluation (also works inline without `=`, e.g. `sqrt(144) + 2^5` or `150 km to mi`) |
| **Bangs** | `!` | — | — | Configurable search & command shortcuts from `~/.config/quickshell/bangs.json` (`!sl`, `!sh`, `!yt`, `!hister`, etc.) |

---

## 2. Hybrid Vector + FTS5 File Content Search

Searching in **All** or **Files (`/`)** mode combines two ranking layers:

1. **Vector Table (`file_vectors`):** Every indexed document (`.pdf`, `.docx`, `.odt`, `.epub`, `.md`, `.txt`, `.tex`, `.typ`, code files) is embedded into a **128-dimensional L2-normalized dense vector** (`float32` `BLOB` in `~/.local/state/quickshell-launcher/content-index.db`) using signed n-gram feature projection over title and body text.
2. **SQLite FTS5 + BM25 (`files_fts`):** Uses `porter unicode61` tokenization with `bm25(files_fts, 10.0, 1.0)` and `snippet()` to extract the exact matching passage from inside PDFs and documents.
3. **Ranking Priority:** Vector similarity matches are weighted `1.6x` and scored above lexical-only and filename-only matches (`file-index.txt`), so typing a phrase from inside a PDF surfaces the exact PDF at the top even if its filename is unrelated.

### Index CLI (`scripts/file_index.py`)

```fish
# Incrementally update vectors, FTS5, and file-index.txt
python3 ~/.config/quickshell/scripts/file_index.py sync

# Query the hybrid index directly from the terminal
python3 ~/.config/quickshell/scripts/file_index.py search "The development of generative artificial intelligence"

# Check indexed file count and SQLite database size
python3 ~/.config/quickshell/scripts/file_index.py stats