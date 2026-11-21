# Launcher bangs

Bangs are prefix commands handled by the Quickshell launcher. Open the launcher,
type a bang beginning with `!`, add a query, and press Enter.

## Built-in bangs

| Bang | What it does | Example |
|---|---|---|
| `!yt` | Searches YouTube | `!yt mechanical linkage simulation` |
| `!g` | Searches Google | `!g steam tables` |
| `!ddg` | Searches DuckDuckGo | `!ddg Arch Linux bluetooth` |
| `!gh` | Searches GitHub | `!gh quickshell notification server` |
| `!aw` | Searches the Arch Wiki | `!aw pipewire` |
| `!aur` | Searches AUR | `!aur hyprland plugin` |
| `!w` | Searches Wikipedia | `!w fluid mechanics` |
| `!maps` | Searches Google Maps | `!maps BIUST` |

Typing only `!` displays the available bang list.

## Editable file

Edit:

```text
~/.config/quickshell/data/data/bangs.json
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

## Supported bang types

- `url`: opens a URL created from `template` and the URL-encoded query.
- `cmd` / `command`: runs `cmd`. A bare `{query}` in the command is replaced by the
  query, which is handed to the shell as a positional argument (`"$1"`) rather than
  pasted into the command text, so a query such as `foo; rm -rf ~` is just an
  argument and cannot run extra commands. Do not wrap `{query}` in your own quotes.
  Without `{query}`, any text after the bang is appended as one extra argument.
- `sh` / `shell`: runs whatever you type after the bang as a shell command. This is
  deliberately a raw shell, like the `>` prefix.

A bang name may contain letters, numbers, `_` and `-`. Aliases use the same
character set. The launcher reloads the configuration on startup; restart or
reload Quickshell (`quickshell ipc call launcher reloadConfig`) after changing the file.
