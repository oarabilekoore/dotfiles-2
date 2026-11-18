import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import ".."

Rectangle {
    id: root

    property var parentBar: null
    property string popupName: "mpris"

    // Find the primary or active player
    readonly property var activePlayer: {
        if (!Mpris.players || !Mpris.players.values || Mpris.players.values.length === 0) return null;
        for (let i = 0; i < Mpris.players.values.length; i++) {
            let p = Mpris.players.values[i];
            if (p && p.isPlaying) return p;
        }
        return Mpris.players.values[0];
    }

    readonly property bool hasMedia: activePlayer !== null && activePlayer.trackTitle && activePlayer.trackTitle.length > 0
    visible: hasMedia
    height: Theme.barHeight
    width: visible ? (contentRow.implicitWidth + 14) : 0
    color: (mouseArea.containsMouse || (parentBar && parentBar.activePopup === popupName)) ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 6

        // Icon
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (!root.activePlayer) return "󰝚";
                if (!root.activePlayer.isPlaying) return "󰏤";
                if (root.activePlayer.identity && root.activePlayer.identity.toLowerCase().indexOf("spotify") !== -1) return "";
                return "󰝚";
            }
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            color: (root.activePlayer && root.activePlayer.isPlaying) ? Theme.foreground : Theme.color7
        }

        // Title text (truncated to 27 chars like waybar)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (!root.activePlayer) return "";
                let title = root.activePlayer.trackTitle || "";
                let artist = root.activePlayer.trackArtist || "";
                let str = artist ? (title + " - " + artist) : title;
                if (str.length > 27) {
                    return str.substring(0, 24) + "...";
                }
                return str;
            }
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            font.italic: root.activePlayer && !root.activePlayer.isPlaying
            color: (root.activePlayer && root.activePlayer.isPlaying) ? Theme.foreground : Theme.color7
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                if (root.activePlayer) root.activePlayer.togglePlaying();
            } else {
                if (parentBar) {
                    parentBar.activePopup = (parentBar.activePopup === root.popupName ? "" : root.popupName);
                }
            }
        }

        onWheel: (wheel) => {
            if (!root.activePlayer) return;
            if (wheel.angleDelta.y < 0) {
                root.activePlayer.next();
            } else {
                root.activePlayer.previous();
            }
        }
    }
}
