import QtQuick
import QtQuick.Layouts
import ".."

// Icon button + slider + value. `value` is 0..1; dragging or clicking emits moved(v).
Item {
    id: root

    property string glyph: ""
    property real value: 0
    property bool muted: false
    property bool showPercent: true
    signal moved(real v)
    signal glyphClicked()

    Layout.fillWidth: true
    implicitHeight: 30

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            radius: 6
            color: glyphMouse.containsMouse ? Theme.surface_variant : "transparent"
            border.color: Theme.outline_variant
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: root.glyph
                font.family: Theme.fontFamily
                font.pixelSize: 15
                color: root.muted ? Theme.on_surface_variant : Theme.foreground
            }
            MouseArea {
                id: glyphMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.glyphClicked()
            }
        }

        Item {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real shown: root.muted ? 0 : Math.max(0, Math.min(1, root.value))

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Theme.outline_variant

                Rectangle {
                    width: parent.width * track.shown
                    height: parent.height
                    radius: 2
                    color: Theme.primary
                }
            }

            Rectangle {
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: (track.width - width) * track.shown
                color: Theme.foreground
                border.color: Theme.primary
                border.width: 2
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function emitAt(px) { root.moved(Math.max(0, Math.min(1, px / track.width))); }
                onPressed: (m) => emitAt(m.x)
                onPositionChanged: (m) => { if (pressed) emitAt(m.x); }
            }
        }

        Text {
            visible: root.showPercent
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: root.muted ? "Mute" : Math.round(root.value * 100) + "%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.on_surface_variant
        }
    }
}
