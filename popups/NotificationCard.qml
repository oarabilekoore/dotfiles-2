import QtQuick
import ".."

// One notification card, drawn to match the SwayNC layout (bottom-centre, 260 wide,
// 4px accent bar on the left, 1px outline, 64px icon, 8px pill progress bar for OSD
// notifications such as volume and brightness). All sizes are logical pixels, so they
// scale with the monitor exactly like the old GTK popups did.
//
// The card is dumb: it renders model roles and emits signals. NotificationDaemon owns
// the Notification objects and decides what each signal does.
Rectangle {
    id: card

    // Model roles supplied by NotificationDaemon's ListModel.
    required property int eid
    required property int rev
    required property string summary
    required property string body
    required property string icon
    required property int urgency      // 0 low, 1 normal, 2 critical
    required property int value        // 0-100 for OSD cards, -1 when there is no progress bar
    required property int timeout      // ms, 0 = stays until dismissed
    required property string actions   // JSON: [{id, text}]

    signal expired()
    signal dismissed()
    signal activated()
    signal actionInvoked(string identifier)

    // Same face as the swaync CSS (JetBrains Mono, 13px, summary weight 600).
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontPx: 13

    readonly property int cardWidth: 260
    readonly property int borderPx: 1
    readonly property int accentPx: 4
    readonly property int pad: 16
    readonly property int iconBox: 64
    readonly property int rowMin: 70
    readonly property int barGap: 14
    readonly property int barHeight: 8

    readonly property bool hasValue: value >= 0
    readonly property bool hasIcon: icon.length > 0
    readonly property var actionList: {
        try { return JSON.parse(actions); } catch (e) { return []; }
    }
    readonly property bool hasActions: actionList.length > 0

    // low = muted, normal = accent, critical = error (swaync: .low / .normal / .critical)
    readonly property color accent: urgency === 2 ? Theme.error
                                  : urgency === 0 ? Theme.color8
                                  : Theme.primary

    readonly property int contentTop: borderPx + pad
    readonly property int textX: hasIcon ? 98 : accentPx + pad
    readonly property int rowHeight: Math.max(hasIcon ? rowMin : 0, textCol.implicitHeight)

    width: cardWidth
    implicitWidth: cardWidth
    implicitHeight: contentTop + rowHeight
                    + (hasValue ? barGap + barHeight : 0)
                    + (hasActions ? 10 + 28 : 0)
                    + pad + borderPx
    height: implicitHeight

    color: Theme.background
    radius: Theme.popupRadius
    border.width: borderPx
    border.color: Theme.alpha(Theme.foreground, 0.28)

    // A repeated notification with the same sync key updates this card in place;
    // start the countdown again.
    onRevChanged: if (!hover.hovered) expiry.restart()

    Timer {
        id: expiry
        interval: card.timeout
        running: card.timeout > 0 && !hover.hovered
        repeat: false
        onTriggered: card.expired()
    }

    HoverHandler { id: hover }

    // Click: run the default action (if any) and dismiss. Right click: dismiss.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) card.dismissed();
            else card.activated();
        }
    }

    // Accent bar, drawn over the left border.
    Rectangle {
        z: 2
        x: 0
        y: 0
        width: card.accentPx
        height: parent.height
        radius: card.radius
        color: card.accent
    }

    Image {
        visible: card.hasIcon
        x: 25
        y: card.contentTop + Math.round((card.rowMin - card.iconBox) / 2)
        width: card.iconBox
        height: card.iconBox
        source: card.icon
        // Rasterise at 2x so SVGs stay sharp at fractional monitor scales.
        sourceSize: Qt.size(card.iconBox * 2, card.iconBox * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Column {
        id: textCol
        x: card.textX
        y: card.contentTop + Math.round((card.rowHeight - height) / 2)
        width: card.width - card.borderPx - card.pad - card.textX
        spacing: 4

        Text {
            width: parent.width
            text: card.summary
            visible: text.length > 0
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: card.fontFamily
            font.pixelSize: card.fontPx
            font.weight: Font.DemiBold
            color: Theme.foreground
        }

        Text {
            width: parent.width
            text: card.body
            visible: text.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 6
            font.family: card.fontFamily
            font.pixelSize: card.fontPx
            color: Theme.alpha(Theme.foreground, 0.85)
        }
    }

    // Progress bar for OSD cards (volume, brightness, microphone).
    Rectangle {
        visible: card.hasValue
        x: card.accentPx + card.pad
        y: card.contentTop + card.rowMin + card.barGap
        width: card.width - card.borderPx - card.pad - x
        height: card.barHeight
        radius: height / 2
        color: Theme.alpha(Theme.foreground, 0.16)

        Rectangle {
            width: Math.round(parent.width * Math.max(0, Math.min(100, card.value)) / 100)
            height: parent.height
            radius: parent.radius
            color: Theme.primary
        }
    }

    // Action buttons (swaync: .action-button).
    Row {
        visible: card.hasActions
        x: card.accentPx + card.pad
        y: card.contentTop + card.rowHeight + (card.hasValue ? card.barGap + card.barHeight : 0) + 10
        spacing: 6

        Repeater {
            model: card.actionList
            delegate: Rectangle {
                id: btn
                required property var modelData
                height: 28
                width: btnText.implicitWidth + 20
                radius: 10
                color: Theme.alpha(Theme.primary, btnArea.containsMouse ? 0.3 : 0.15)
                border.width: 1
                border.color: Theme.alpha(Theme.primary, 0.35)

                Text {
                    id: btnText
                    anchors.centerIn: parent
                    text: btn.modelData.text
                    textFormat: Text.PlainText
                    font.family: card.fontFamily
                    font.pixelSize: card.fontPx
                    color: Theme.foreground
                }

                MouseArea {
                    id: btnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.actionInvoked(btn.modelData.id)
                }
            }
        }
    }

    // Close button, only while hovered (swaync shows one too).
    Text {
        visible: hover.hovered
        z: 3
        x: card.width - card.borderPx - 8 - width
        y: card.borderPx + 6
        text: "×"
        font.family: card.fontFamily
        font.pixelSize: card.fontPx + 5
        color: Theme.alpha(Theme.foreground, closeArea.containsMouse ? 1.0 : 0.5)

        MouseArea {
            id: closeArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.dismissed()
        }
    }
}
