import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."

Row {
    id: root
    spacing: 1

    readonly property var romanNumerals: ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
    readonly property var persistentWorkspaces: [1, 2, 3, 4, 5]

    Repeater {
        model: 10

        delegate: Rectangle {
            id: wsBtn
            required property int index
            readonly property int wsId: index + 1
            readonly property string roman: root.romanNumerals[index]

            // Check if this workspace is active or exists in Hyprland
            readonly property var wsObj: {
                if (!Hyprland.workspaces || !Hyprland.workspaces.values) return null;
                for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
                    let w = Hyprland.workspaces.values[i];
                    if (w && w.id === wsId) return w;
                }
                return null;
            }

            readonly property bool isFocused: Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.id === wsId) : false
            readonly property bool isOccupied: wsObj !== null
            readonly property bool isPersistent: root.persistentWorkspaces.indexOf(wsId) !== -1

            visible: isPersistent || isOccupied || isFocused
            width: wsText.implicitWidth + 21
            height: Theme.barHeight
            color: mouseArea.containsMouse ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
            radius: Theme.moduleRadius

            Text {
                id: wsText
                anchors.centerIn: parent
                text: wsBtn.roman
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                color: wsBtn.isFocused ? Theme.foreground : Theme.color15
                opacity: wsBtn.isFocused ? 1.0 : (wsBtn.isOccupied ? 0.85 : 0.35)

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsBtn.wsId + " })");
                }
            }
        }
    }
}
