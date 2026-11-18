import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

PopupBase {
    id: root

    popupName: "calendar"
    popupGravity: Edges.Bottom          // centred under the clock
    // Horizontal layout: month grid on the left, agenda on the right.
    implicitWidth: 14 + 264 + 14 + 1 + 14 + 270 + 14
    implicitHeight: calLayout.implicitHeight + 28

    property var today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()      // 0-11
    property int selectedDay: -1                  // day-of-month in the viewed month, -1 = none
    property var events: []                       // [{title, allDay, start: Date, end: Date}]
    property double fetchFromMs: 0
    property double fetchToMs: 0
    property string statusText: ""

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var dayHeaders: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function isoDate(y, m, d) { return y + "-" + pad(m + 1) + "-" + pad(d); }
    function fmtTime(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()); }
    function fmtDay(d) { return dayNames[d.getDay()] + " " + d.getDate() + " " + monthNames[d.getMonth()].substring(0, 3); }

    // ---- events ---------------------------------------------------------------
    function fetchEvents(year, month) {
        const from = new Date(year, month - 1, 1);
        const to = new Date(year, month + 3, 1);
        root.fetchFromMs = from.getTime();
        root.fetchToMs = to.getTime();
        const days = Math.round((to.getTime() - from.getTime()) / 86400000);
        eventsProc.running = false;
        eventsProc.command = ["hydrogen", "calendar", "list",
                              "--from", isoDate(from.getFullYear(), from.getMonth(), 1), "--days", String(days)];
        eventsProc.running = true;
    }

    function ensureRange() {
        const first = new Date(viewYear, viewMonth, 1).getTime();
        const last = new Date(viewYear, viewMonth + 1, 1).getTime();
        if (first < fetchFromMs || last > fetchToMs) fetchEvents(viewYear, viewMonth);
    }

    function parseEvents(txt) {
        const list = [];
        try {
            const arr = JSON.parse(txt && txt.length ? txt : "[]");
            for (const e of arr) {
                list.push({ title: e.title, allDay: e.allDay, start: new Date(e.start), end: new Date(e.end) });
            }
        } catch (err) {
            console.warn("calendar: could not parse events:", err);
        }
        root.events = list;
    }

    function eventsOn(y, m, d) {
        const s = new Date(y, m, d).getTime();
        const e = new Date(y, m, d + 1).getTime();
        return root.events.filter(ev => ev.start.getTime() < e && ev.end.getTime() > s);
    }

    readonly property var upcoming: {
        const now = Date.now();
        const limit = now + 14 * 86400000;
        return root.events.filter(ev => ev.end.getTime() > now && ev.start.getTime() < limit).slice(0, 12);
    }

    readonly property var selectedEvents: selectedDay > 0 ? eventsOn(viewYear, viewMonth, selectedDay) : []
    readonly property var listEvents: selectedDay > 0 ? selectedEvents : upcoming

    // ---- default-calendar integration ---------------------------------------
    function scheduleEvent() {
        const title = titleField.text.trim().length > 0 ? titleField.text.trim() : "New event";
        const tm = timeField.text.trim();
        if (tm.length > 0 && !/^\d{1,2}:\d{2}$/.test(tm)) {
            root.statusText = "Time looks like 14:30 (leave empty for all-day)";
            return;
        }
        scheduleProc.command = ["hydrogen", "calendar", "add",
                                isoDate(viewYear, viewMonth, selectedDay), tm.length > 0 ? tm : "allday", title];
        scheduleProc.running = true;
        titleField.text = "";
        root.dismiss();
    }

    function openCalendar(dayOrNone) {
        openProc.command = dayOrNone > 0
            ? ["hydrogen", "calendar", "open", isoDate(viewYear, viewMonth, dayOrNone)]
            : ["hydrogen", "calendar", "open"];
        openProc.running = false;
        openProc.running = true;
        root.dismiss();
    }

    Process {
        id: eventsProc
        stdout: StdioCollector {
            onStreamFinished: root.parseEvents(text)
        }
    }
    Process { id: scheduleProc }
    Process { id: openProc }

    onVisibleChanged: {
        if (visible) {
            root.today = new Date();
            root.viewYear = root.today.getFullYear();
            root.viewMonth = root.today.getMonth();
            root.selectedDay = -1;
            root.statusText = "";
            root.fetchEvents(root.viewYear, root.viewMonth);
        }
    }

    function shiftMonth(delta) {
        let m = viewMonth + delta;
        let y = viewYear;
        while (m < 0) { m += 12; y--; }
        while (m > 11) { m -= 12; y++; }
        viewYear = y;
        viewMonth = m;
        selectedDay = -1;
        ensureRange();
    }


    // ---- UI ----------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        border.color: Theme.outline_variant
        border.width: 1
        radius: Theme.popupRadius

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            // ---------------- LEFT: month grid ----------------
            ColumnLayout {
                id: calLayout
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 264
                spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.monthNames[root.viewMonth] + " " + root.viewYear
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    color: Theme.foreground
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 24
                    radius: 4
                    color: todayMouse.containsMouse ? Theme.surface_variant : "transparent"
                    border.color: Theme.outline_variant
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Today"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.primary
                    }

                    MouseArea {
                        id: todayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.today = new Date();
                            root.viewYear = root.today.getFullYear();
                            root.viewMonth = root.today.getMonth();
                            root.selectedDay = -1;
                            root.ensureRange();
                        }
                    }
                }

                IconButton {
                    implicitWidth: 24
                    implicitHeight: 24
                    glyph: "󰅁"
                    onClicked: root.shiftMonth(-1)
                }

                IconButton {
                    implicitWidth: 24
                    implicitHeight: 24
                    glyph: "󰅂"
                    onClicked: root.shiftMonth(1)
                }
            }

            // Weekday headers
            Grid {
                columns: 7
                columnSpacing: 2
                rowSpacing: 2
                Layout.alignment: Qt.AlignHCenter

                Repeater {
                    model: root.dayHeaders

                    delegate: Item {
                        required property string modelData
                        width: 36
                        height: 18

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.bold: true
                            color: Theme.on_surface_variant
                        }
                    }
                }
            }

            // Day grid: 6 rows x 7 columns
            Grid {
                id: daysGrid
                columns: 7
                columnSpacing: 2
                rowSpacing: 2
                Layout.alignment: Qt.AlignHCenter

                readonly property int firstDayOfWeek: {
                    const d = new Date(root.viewYear, root.viewMonth, 1).getDay();
                    return d === 0 ? 6 : d - 1;      // 0 = Monday
                }
                readonly property int daysInMonth: new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
                readonly property int daysInPrevMonth: new Date(root.viewYear, root.viewMonth, 0).getDate()

                Repeater {
                    model: 42

                    delegate: Rectangle {
                        id: cell
                        required property int index

                        readonly property int dayOffset: index - daysGrid.firstDayOfWeek + 1
                        readonly property bool isCurrentMonth: dayOffset >= 1 && dayOffset <= daysGrid.daysInMonth
                        readonly property int displayDay: {
                            if (isCurrentMonth) return dayOffset;
                            if (dayOffset < 1) return daysGrid.daysInPrevMonth + dayOffset;
                            return dayOffset - daysGrid.daysInMonth;
                        }
                        readonly property bool isToday: isCurrentMonth
                            && displayDay === root.today.getDate()
                            && root.viewMonth === root.today.getMonth()
                            && root.viewYear === root.today.getFullYear()
                        readonly property bool isSelected: isCurrentMonth && displayDay === root.selectedDay
                        readonly property bool hasEvents: isCurrentMonth && root.eventsOn(root.viewYear, root.viewMonth, displayDay).length > 0

                        width: 36
                        height: 32
                        radius: 6
                        color: isToday ? Theme.primary
                             : (isSelected ? Theme.alpha(Theme.primary, 0.3)
                             : (dayMouse.containsMouse && isCurrentMonth ? Theme.surface_variant : "transparent"))
                        border.color: (isSelected && isToday) ? Theme.on_primary : "transparent"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: cell.hasEvents ? -2 : 0
                            text: cell.displayDay
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.bold: cell.isToday || cell.isSelected
                            color: cell.isToday ? Theme.on_primary
                                 : (cell.isCurrentMonth ? Theme.foreground : Theme.alpha(Theme.foreground, 0.3))
                        }

                        // Event dot
                        Rectangle {
                            visible: cell.hasEvents
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            width: 4
                            height: 4
                            radius: 2
                            color: cell.isToday ? Theme.on_primary : Theme.secondary
                        }

                        MouseArea {
                            id: dayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: cell.isCurrentMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!cell.isCurrentMonth) return;
                                root.selectedDay = (root.selectedDay === cell.displayDay) ? -1 : cell.displayDay;
                                root.statusText = "";
                            }
                            onDoubleClicked: {
                                if (cell.isCurrentMonth) root.openCalendar(cell.displayDay);
                            }
                        }
                    }
                }
            }
            }

            // vertical divider
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: Theme.outline_variant
            }

            // ---------------- RIGHT: agenda ----------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 270
                spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: root.selectedDay > 0
                          ? root.fmtDay(new Date(root.viewYear, root.viewMonth, root.selectedDay)).toUpperCase()
                          : "UPCOMING"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    color: Theme.on_surface_variant
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.selectedDay < 0
                    text: "next 14 days"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.outline
                }
            }

                // Scrollable event list; the popup keeps the calendar's height
                Flickable {
                    id: evFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: evCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: evCol
                        width: evFlick.width
                        spacing: 4

                Repeater {
                    model: root.listEvents

                    delegate: Rectangle {
                        id: evRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: 6
                        color: Theme.surface_variant

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            width: 3
                            radius: 1.5
                            color: Theme.secondary
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 10
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: evRow.modelData.title
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: Theme.foreground
                            }
                            Text {
                                Layout.fillWidth: true
                                text: {
                                    const e = evRow.modelData;
                                    const when = e.allDay ? "All day" : root.fmtTime(e.start) + " - " + root.fmtTime(e.end);
                                    return root.selectedDay > 0 ? when : root.fmtDay(e.start) + "  ·  " + when;
                                }
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.on_surface_variant
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.listEvents.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: root.selectedDay > 0 ? "Nothing scheduled on this day" : "No upcoming events"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.on_surface_variant
                }
                    }
                }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.selectedDay > 0
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 4
                        color: Theme.surface
                        border.color: titleField.activeFocus ? Theme.primary : Theme.outline_variant
                        border.width: 1

                        TextInput {
                            id: titleField
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            selectByMouse: true
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.foreground
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.on_primary
                            onAccepted: root.scheduleEvent()
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            visible: titleField.text.length === 0
                            text: "New event title"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.outline
                        }
                    }

                    Rectangle {
                        implicitWidth: 60
                        implicitHeight: 30
                        radius: 4
                        color: Theme.surface
                        border.color: timeField.activeFocus ? Theme.primary : Theme.outline_variant
                        border.width: 1

                        TextInput {
                            id: timeField
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            text: "09:00"
                            maximumLength: 5
                            selectByMouse: true
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.foreground
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.on_primary
                            onAccepted: root.scheduleEvent()
                        }
                    }

                    IconButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        glyph: "󰐕"
                        active: true
                        onClicked: root.scheduleEvent()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.statusText.length > 0 ? root.statusText
                          : "Opens your default calendar with the event filled in. Double-click a date to open it there."
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: root.statusText.length > 0 ? Theme.error : Theme.outline
                }
            }

                FooterButton {
                    Layout.fillWidth: true
                    glyph: "󰃭"
                    label: "Open Calendar"
                    onClicked: root.openCalendar(root.selectedDay)
                }
            }
        }
    }
}