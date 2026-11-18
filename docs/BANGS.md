# Launcher bangs

Bangs are prefix commands handled by the Quickshell launcher. Open the launcher,
type a bang beginning with `!`, add a query, and press Enter.

## Built-in bangs

| Bang | What it does | Example |
|---|---|---|
| `!ai` | Sends a prompt to the AI provider selected in Apps & AI | `!ai explain Euler's equations` |
| `!yt` | Searches YouTube | `!yt mechanical linkage simulation` |
| `!hister` | Opens the native Hister web interface with your query | `!hister thermodynamics notes` |
| `!h` / `!his` | Aliases for Hister | `!h exam timetable` |
| `!g` | Searches Google | `!g steam tables` |
| `!ddg` | Searches DuckDuckGo | `!ddg Arch Linux bluetooth` |
| `!gh` | Searches GitHub | `!gh quickshell notification server` |
| `!aw` | Searches the Arch Wiki | `!aw pipewire` |
| `!aur` | Searches AUR | `!aur hyprland plugin` |
| `!w` | Searches Wikipedia | `!w fluid mechanics` |
| `!maps` | Searches Google Maps | `!maps BIUST` |

Typing only `!` displays the available bang list. Normal All-mode searches also
include results from the Hister HTTP search API. `!hister` opens Hister's own
web interface in your default browser, preserving its native results and
preview experience.

## Editable file

Edit:

```text
~/.config/quickshell/bangs.json
```

The file is a JSON array. Each object needs a unique `bang`, a `type`, and the
fields required by that type. Do not include the leading `!` in the JSON value.

## Add a URL bang

Add an object whose `template` contains `{query}` where the URL-encoded search
term belongs:

```json
{
  "bang": "yt",
  "label": "YouTube",
  "type": "url",
  "template": "https://www.youtube.com/results?search_query={query}"
}
```

Then use `!yt planetary gear animation`.

## Add an AI alias

```json
{
  "bang": "ask",
  "aliases": ["assistant"],
  "label": "AI Assistant",
  "type": "ai"
}
```

This sends `!ask explain the Coriolis effect` to the configured AI provider.

## Hister configuration

Hister should be running locally (default URL `http://127.0.0.1:4433`). The
server URL is editable in Control Center → Apps & AI → Hister Personal Search
and is saved as `histerServerUrl` in `~/.config/quickshell/settings.json`.

- Normal All-mode launcher searches call Hister's `/search?format=json&q=...`
  endpoint and display matching indexed pages alongside app/file results.
- `!hister query` opens `http://127.0.0.1:4433/?q=query` (using your configured
  server URL) in the default browser. Hister's own web interface handles the
  query, results, history and previews.

The launcher uses `curl` for local API requests. Install it if it is missing.

## Supported bang types

- `url`: opens a URL created from `template` and the query.
- `ai`: sends the query to the configured AI provider.
- `hister`: opens the Hister web interface with the query.

A bang name may contain letters, numbers, `_` and `-`. Aliases use the same
character set. The launcher reloads the configuration on startup; restart or
reload Quickshell after changing the file.
