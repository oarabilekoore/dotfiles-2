# Notifications and status toasts

Quickshell owns the session's `org.freedesktop.Notifications` service through
`NotificationDaemon.qml`. It renders notifications with the shared
`popups/NotificationCard.qml` component.

## Behaviour

- Normal notifications stay for 5 seconds; low-urgency notifications stay for
  3 seconds; critical notifications remain until dismissed.
- Notifications carrying `x-canonical-private-synchronous` replace the
  existing card with the same key. This is used for OSD and toggle feedback.
- Notifications carrying a numeric `value` hint (0-100) render a progress bar.
- Do Not Disturb hides ordinary notifications but leaves OSD and critical
  notifications visible.
- Status notifications without an application icon receive a Nerd Font glyph
  when their title/body identifies airplane mode, caffeine, mute/volume,
  Caps Lock, or mouse/touchpad state.

## Existing toggle integrations

- Caffeine is controlled by `~/.config/hypr/scripts/caffeine.sh toggle`.
  The bar watches `/tmp/caffeine_on` only to update its icon. The existing
  `caffeine.sh` script owns the toggle notification, avoiding duplicate toasts.
- The volume module's right-click mute action calls
  `prgnotifier volume toggle`, matching the hardware mute key's OSD path.
- Airplane mode and touchpad blocking are handled by the user's separate
  `~/.config/hypr/scripts/sysnotifier.sh` script. Keep its notifications
  descriptive (for example, titles containing "Airplane mode" or "Touchpad")
  to select the matching glyph automatically.

## Test

Send sample notifications:

```sh
notify-send "Airplane mode" "Enabled"
notify-send "Caffeine" "Enabled"
notify-send "Volume" "Muted"
notify-send "Caps Lock" "On"
notify-send "Touchpad" "Disabled"
```

The daemon is started by `shell.qml`. Do not start SwayNC, mako, dunst, or
another notification server alongside it: D-Bus notification ownership is
exclusive.
