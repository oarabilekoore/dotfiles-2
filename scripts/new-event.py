#!/usr/bin/env python3
"""Hand a new event to the default calendar application.

usage: new-event.py YYYY-MM-DD HH:MM|allday TITLE...

Writes a one-event .ics file and opens it with the system default handler for text/calendar
(GNOME Calendar, Evolution, Thunderbird, ...), which then lets you pick the calendar and save.
Set DURATION=<minutes> in the environment to change the default 60 minute length.
"""
import os
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone


def esc(s):
    return s.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: new-event.py YYYY-MM-DD HH:MM|allday TITLE...")
    date_s, time_s = sys.argv[1], sys.argv[2]
    title = " ".join(sys.argv[3:]).strip() or "New event"
    duration = int(os.environ.get("DURATION", "60"))

    if time_s in ("", "allday"):
        d = datetime.strptime(date_s, "%Y-%m-%d")
        dtstart = "DTSTART;VALUE=DATE:%s" % d.strftime("%Y%m%d")
        dtend = "DTEND;VALUE=DATE:%s" % (d + timedelta(days=1)).strftime("%Y%m%d")
    else:
        s = datetime.strptime("%s %s" % (date_s, time_s), "%Y-%m-%d %H:%M")
        e = s + timedelta(minutes=duration)
        dtstart = "DTSTART:%s" % s.strftime("%Y%m%dT%H%M%S")   # floating local time
        dtend = "DTEND:%s" % e.strftime("%Y%m%dT%H%M%S")

    uid = uuid.uuid4().hex
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    ics = "\r\n".join([
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//quickshell//bar//EN",
        "BEGIN:VEVENT", "UID:%s@quickshell" % uid, "DTSTAMP:%s" % stamp,
        dtstart, dtend, "SUMMARY:%s" % esc(title),
        "END:VEVENT", "END:VCALENDAR", "",
    ])
    path = os.path.join(tempfile.gettempdir(), "qs-event-%s.ics" % uid[:8])
    with open(path, "w", newline="") as fh:
        fh.write(ics)
    subprocess.Popen(["xdg-open", path], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
