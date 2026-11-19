# Notifications and OSD

This configuration deliberately delegates desktop notifications to **SwayNC**.
Quickshell does not instantiate a `NotificationServer`, so it does not compete
with SwayNC for the session's `org.freedesktop.Notifications` D-Bus name.

## Ownership

- **SwayNC** owns desktop notifications and the notification centre.
- **Quickshell** provides the bar, launcher and control centre.
- The Quickshell OSD is disabled in the current shell entry point. Volume,
  brightness and other helper scripts may still invoke their configured
  external OSD integration, but this repository does not create a competing
  Quickshell OSD surface.

Do not enable a second notification server while SwayNC is running. D-Bus
notification ownership is exclusive; two daemons cannot both own the same
well-known name.

## Verify SwayNC

Check that the service is running:

```sh
pgrep -a swaync
```

Send a test notification:

```sh
notify-send "Notification test" "SwayNC should display this message."
```

If notifications do not appear, inspect the SwayNC process and its user
configuration before changing Quickshell. Also check that no other daemon
(mako, dunst, fnott or a Quickshell notification server) is started alongside
it.

## Configuration

SwayNC appearance and behaviour are controlled by its own configuration,
typically under `~/.config/swaync/`. Quickshell's `Theme.qml` palette is a
separate concern and does not automatically theme SwayNC.
