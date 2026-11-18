#!/usr/bin/env python3
"""Print upcoming calendar events as JSON for the Quickshell calendar popup.

usage: events.py [--from YYYY-MM-DD] [--days N]

Reads iCalendar data from the places desktop calendars keep it:
  * GNOME Calendar / Evolution local calendars   ~/.local/share/evolution/calendar/*/calendar.ics
  * GNOME Calendar / Evolution online accounts   ~/.cache/evolution/calendar/*/cache.db  (read-only snapshot)
  * vdirsyncer / khal / generic .ics folders     ~/.calendars, ~/.local/share/{vdirsyncer,khal}, ~/.config/quickshell/calendars
Recurring events (DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, COUNT, UNTIL, BYDAY on weekly) are expanded.
"""
import glob
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

HOME = os.path.expanduser("~")
ICS_GLOBS = [
    HOME + "/.local/share/evolution/calendar/*/calendar.ics",
    HOME + "/.calendars/**/*.ics",
    HOME + "/.local/share/vdirsyncer/**/*.ics",
    HOME + "/.local/share/khal/**/*.ics",
    HOME + "/.config/quickshell/calendars/**/*.ics",
]
DB_GLOBS = [HOME + "/.cache/evolution/calendar/*/cache.db"]
WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def read_texts():
    for pattern in ICS_GLOBS:
        for path in glob.glob(pattern, recursive=True):
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    yield fh.read()
            except OSError:
                pass
    for pattern in DB_GLOBS:
        for path in glob.glob(pattern):
            try:
                con = sqlite3.connect("file:%s?mode=ro&immutable=1" % path, uri=True)
                for (obj,) in con.execute("SELECT ECacheOBJ FROM ECacheObjects"):
                    if obj:
                        yield obj
                con.close()
            except Exception:
                pass


def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).splitlines()


def split_events(text):
    cur = None
    for line in unfold(text):
        up = line.upper()
        if up.startswith("BEGIN:VEVENT"):
            cur = []
        elif up.startswith("END:VEVENT"):
            if cur is not None:
                yield cur
            cur = None
        elif cur is not None:
            cur.append(line)


def props(lines, name):
    """Return every (params, value) pair for property `name`."""
    found = []
    for line in lines:
        key, _, val = line.partition(":")
        base, *params = key.split(";")
        if base.upper() == name:
            pd = {}
            for p in params:
                if "=" in p:
                    k, v = p.split("=", 1)
                    pd[k.upper()] = v.strip('"')
            found.append((pd, val))
    return found


def unescape(s):
    return s.replace("\\n", " ").replace("\\N", " ").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")


def parse_dt(params, val):
    """-> (naive local datetime, all_day)"""
    val = val.strip()
    if params.get("VALUE") == "DATE" or len(val) == 8:
        return datetime.strptime(val[:8], "%Y%m%d"), True
    if val.endswith("Z"):
        d = datetime.strptime(val, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        return d.astimezone().replace(tzinfo=None), False
    d = datetime.strptime(val[:15], "%Y%m%dT%H%M%S")
    tz = params.get("TZID")
    if tz and ZoneInfo:
        try:
            d = d.replace(tzinfo=ZoneInfo(tz)).astimezone().replace(tzinfo=None)
        except Exception:
            pass
    return d, False


def add_months(d, n):
    m = d.month - 1 + n
    y = d.year + m // 12
    m = m % 12 + 1
    try:
        return d.replace(year=y, month=m)
    except ValueError:
        return None  # e.g. the 31st in a 30-day month: skipped, as RFC 5545 says


def nth(start, freq, interval, k):
    """k-th repeat of `start` (k=0 is the start itself); None when the date does not exist."""
    if freq == "DAILY":
        return start + timedelta(days=interval * k)
    if freq == "WEEKLY":
        return start + timedelta(weeks=interval * k)
    if freq == "MONTHLY":
        return add_months(start, interval * k)
    if freq == "YEARLY":
        try:
            return start.replace(year=start.year + interval * k)
        except ValueError:
            return None
    return None


def expand(start, rrule, exdates, duration, win_start, win_end):
    def visible(s):
        return s + duration >= win_start and s < win_end and s not in exdates and s.date() not in exdates

    if not rrule:
        return [start] if visible(start) else []

    parts = dict(p.split("=", 1) for p in rrule.split(";") if "=" in p)
    freq = parts.get("FREQ", "")
    interval = max(1, int(parts.get("INTERVAL", "1")))
    count = int(parts["COUNT"]) if "COUNT" in parts else None
    until = None
    if "UNTIL" in parts:
        until, all_day = parse_dt({}, parts["UNTIL"])
        if all_day:
            until = until.replace(hour=23, minute=59, second=59)
    byday = [d[-2:] for d in parts.get("BYDAY", "").split(",") if d[-2:] in WEEKDAYS]

    out, n, k, guard = [], 0, 0, 0
    cur = start
    while cur is None or cur < win_end:
        guard += 1
        if guard > 6000:
            break
        if cur is None:                       # e.g. the 31st in a 30-day month: skipped (RFC 5545)
            k += 1
            cur = nth(start, freq, interval, k)
            continue
        if freq == "WEEKLY" and byday:
            monday = cur - timedelta(days=cur.weekday())
            cands = sorted(datetime.combine((monday + timedelta(days=WEEKDAYS.index(d))).date(), start.time()) for d in byday)
            cands = [c for c in cands if c >= start]
        else:
            cands = [cur]
        stop = False
        for c in cands:
            if (until and c > until) or (count is not None and n >= count):
                stop = True
                break
            n += 1
            if visible(c):
                out.append(c)
        if stop or freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
            break
        k += 1
        cur = nth(start, freq, interval, k)
    return out


def main():
    args = sys.argv[1:]
    start_day = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    days = 60
    for i, a in enumerate(args):
        if a == "--from" and i + 1 < len(args):
            start_day = datetime.strptime(args[i + 1], "%Y-%m-%d")
        elif a == "--days" and i + 1 < len(args):
            days = int(args[i + 1])
    win_start, win_end = start_day, start_day + timedelta(days=days)

    seen, result = set(), []
    for text in read_texts():
        for ev in split_events(text):
            try:
                ds = props(ev, "DTSTART")
                if not ds:
                    continue
                start, all_day = parse_dt(*ds[0])
                de = props(ev, "DTEND")
                if de:
                    end, _ = parse_dt(*de[0])
                    duration = max(end - start, timedelta(0))
                else:
                    duration = timedelta(days=1) if all_day else timedelta(0)
                title = unescape(props(ev, "SUMMARY")[0][1]) if props(ev, "SUMMARY") else "(no title)"
                rr = props(ev, "RRULE")
                exdates = set()
                for pd, val in props(ev, "EXDATE"):
                    for v in val.split(","):
                        d, ad = parse_dt(pd, v)
                        exdates.add(d.date() if ad else d)
                for occ in expand(start, rr[0][1] if rr else None, exdates, duration, win_start, win_end):
                    key = (title, occ)
                    if key in seen:
                        continue
                    seen.add(key)
                    result.append({
                        "title": title,
                        "start": occ.strftime("%Y-%m-%dT%H:%M:%S"),
                        "end": (occ + duration).strftime("%Y-%m-%dT%H:%M:%S"),
                        "allDay": all_day,
                    })
            except Exception:
                continue

    result.sort(key=lambda e: e["start"])
    json.dump(result[:400], sys.stdout)


if __name__ == "__main__":
    main()
