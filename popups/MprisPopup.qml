import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import ".."

PopupBase {
    id: root

    property var player: null

    popupName: "mpris"
    popupGravity: Edges.Bottom | Edges.Right
    implicitWidth: 320
    implicitHeight: mainLayout.implicitHeight + 28

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.surface
        border.color: Theme.outline_variant
        border.width: 1
        radius: Theme.popupRadius

        ColumnLayout {
            id: mainLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            // Top Header: Player identity
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.player ? (root.player.identity || "Media Player") : "No Media Player"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    color: Theme.on_surface_variant
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.player && root.player.isPlaying ? "Playing" : "Paused"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    color: root.player && root.player.isPlaying ? Theme.success : Theme.on_surface_variant
                }
            }

            // Media Info: Art + Title/Artist
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 56
                    height: 56
                    radius: 4
                    color: Theme.surface_variant
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: (root.player && root.player.identity && root.player.identity.toLowerCase().indexOf("spotify") !== -1) ? "" : "󰝚"
                        font.family: Theme.fontFamily
                        font.pixelSize: 24
                        color: Theme.primary
                        visible: !(root.player && root.player.trackArtUrl)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: (root.player && root.player.trackTitle) ? root.player.trackTitle : "No media playing"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.foreground
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: (root.player && root.player.trackArtist) ? root.player.trackArtist : "Unknown Artist"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.on_surface_variant
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: (root.player && root.player.trackAlbum) ? root.player.trackAlbum : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.outline
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                }
            }

            // Progress bar
            Rectangle {
                Layout.fillWidth: true
                height: 4
                radius: 2
                color: Theme.surface_variant
                visible: !!root.player && root.player.lengthSupported && root.player.length > 0

                Rectangle {
                    width: (root.player && root.player.length > 0) ? Math.min(parent.width, parent.width * (root.player.position / root.player.length)) : 0
                    height: parent.height
                    radius: 2
                    color: Theme.primary
                }
            }

            // Playback Controls Row
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20

                // Previous
                Rectangle {
                    width: 32
                    height: 32
                    radius: 4
                    color: prevMouse.containsMouse ? Theme.surface_variant : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰒮"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        color: root.player && root.player.canGoPrevious ? Theme.foreground : Theme.outline
                    }

                    MouseArea {
                        id: prevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.previous()
                    }
                }

                // Play / Pause
                Rectangle {
                    width: 38
                    height: 38
                    radius: 19
                    color: playMouse.containsMouse ? Theme.primary : Theme.surface_variant
                    border.color: Theme.outline
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        color: Theme.foreground
                    }

                    MouseArea {
                        id: playMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.togglePlaying()
                    }
                }

                // Next
                Rectangle {
                    width: 32
                    height: 32
                    radius: 4
                    color: nextMouse.containsMouse ? Theme.surface_variant : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰒭"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        color: root.player && root.player.canGoNext ? Theme.foreground : Theme.outline
                    }

                    MouseArea {
                        id: nextMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.next()
                    }
                }
            }
        }
    }
}
