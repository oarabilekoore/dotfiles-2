# Quickshell memory tuning

This shell uses Quickshell's `LazyLoader` for expensive windows and popup trees. A hidden `PanelWindow` is still a live QML object tree; setting `visible: false` hides its surface but does not destroy its objects. Lazy loading avoids constructing these trees until they are needed.

## What is deferred

- The main launcher is created on its first IPC open and destroyed 2.2 seconds after it closes. The short grace period allows the close animation to finish and avoids destroying it during a quick reopen.
- The full settings/control-center window is created on demand and destroyed 1.4 seconds after closing.
- Each bar popup (Wi-Fi, Bluetooth, volume, battery, tray menu, compact settings, calendar, and media controls) exists only while that popup is selected. Closing it releases its QML object tree and its service bindings.
- The clock label is bound to a minute-precision `SystemClock` (no timer of its own), and the Caffeine indicator watches its flag file instead of spawning a process every few seconds.

## Behaviour and trade-offs

- First opening the launcher or settings window now has a small construction cost. Subsequent opens during the grace period reuse the existing object.
- Launcher state is still read from disk on creation. Its initial file-index refresh now happens when the launcher is first opened (or when the reindex IPC action is called), rather than at shell startup; this avoids launching Hydrogen just to prepare a launcher that may never be used.
- Settings refreshes system state when opened. Its former startup refresh was removed because the first `present()` already refreshes those same sources.
- Bar modules remain resident because they provide always-visible status indicators. Their service bindings are event-driven; the shell does not spawn a polling process for every module.
- No visual effects, blur, shadows, or functionality were removed.

## Measure the result

Record Quickshell's RSS after the desktop settles, then compare after opening and closing the launcher and settings:

```sh
pid=$(pgrep -n quickshell)
ps -p "$pid" -o pid,comm,rss,%cpu
```

For a more detailed view:

```sh
watch -n 2 'ps -C quickshell -o pid,rss,%cpu,etime --sort=-rss'
```

RSS is resident memory in KiB. Compare measurements under the same monitor layout and with the same tray applications running. The changes reduce the number of live QML objects, but the actual RSS reduction depends on which windows and popups you use.
