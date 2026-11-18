#!/bin/sh
# usage: open-calendar.sh [YYYY-MM-DD]
# Opens the system default calendar (the handler registered for text/calendar).
handler=$(xdg-mime query default text/calendar 2>/dev/null)

case "$handler" in
  *gnome-calendar*|"")
    if command -v gnome-calendar >/dev/null 2>&1; then
      if [ -n "$1" ]; then exec gnome-calendar --date "$1"; fi
      exec gnome-calendar
    fi
    ;;
esac

if [ -n "$handler" ]; then
  exec gtk-launch "$handler"
fi

echo "No default calendar application found (xdg-mime query default text/calendar is empty)" >&2
exit 1
