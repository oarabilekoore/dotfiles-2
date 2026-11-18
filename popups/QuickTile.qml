import QtQuick
import QtQuick.Layouts
import ".."

// Windows 11 / GNOME style quick-setting tile: filled with the accent colour when on.
// The body toggles; the optional chevron on the right opens the detailed popup.
Rectangle {
    id: root

    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool hasDetail: false
    signal clicked()
    signal detailClicked()

    Layout.fillWidth: true
    Layout.preferredWidth: 1            // equal column widths
    implicitHeight: 52
    radius: 8
    color: active ? (bodyMouse.containsMouse ? Qt.lighter(Theme.primary, 1.1) : Theme.primary)
                  : (bodyMouse.containsMouse ? Theme.alpha(Theme.foreground, 0.10) : Theme.surface_variant)
    border.color: active ? "transparent" : Theme.outline_variant
    border.width: 1

    Behavior on color { ColorAnimation { duration: 100 } }

    MouseArea {
        id: bodyMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: root.hasDetail ? 4 : 10
        spacing: 10

        Text {
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph
            font.family: Theme.fontFamily
            font.pixelSize: 18
            color: root.active ? Theme.on_primary : Theme.foreground
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: root.active ? Theme.on_primary : Theme.foreground
            }
            Text {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: root.active ? Theme.alpha(Theme.on_primary, 0.8) : Theme.on_surface_variant
            }
        }

        Item {
            visible: root.hasDetail
            Layout.preferredWidth: 26
            Layout.fillHeight: true

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 30
                radius: 6
                color: detailMouse.containsMouse ? Theme.alpha(Theme.foreground, 0.15) : "transparent"
            }
            Text {
                anchors.centerIn: parent
                text: "󰅂"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: root.active ? Theme.on_primary : Theme.on_surface_variant
            }
            MouseArea {
                id: detailMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.detailClicked()
            }
        }
    }
}
