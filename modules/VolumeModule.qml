import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import ".."

Rectangle {
    id: root

    property var parentBar: null
    property string popupName: "volume"

    readonly property var sink: Pipewire.defaultAudioSink

    // PipeWire nodes only publish volume/mute once something has bound them;
    // without this tracker sink.audio stays unbound and reads stale values.
    PwObjectTracker {
        objects: [root.sink]
    }

    readonly property bool isMuted: sink && sink.audio ? sink.audio.muted : false
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0.0

    readonly property string volumeIcon: {
        if (isMuted) return "";
        if (volume <= 0.01) return "";
        if (volume < 0.5) return "";
        return "";
    }

    height: Theme.barHeight
    width: Theme.moduleWidth
    color: (mouseArea.containsMouse || (parentBar && parentBar.activePopup === popupName)) ? Theme.alpha(Theme.foreground, 0.08) : "transparent"
    radius: Theme.moduleRadius

    Text {
        id: volIcon
        anchors.centerIn: parent
        text: root.volumeIcon
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: root.isMuted ? Theme.color7 : Theme.foreground
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                // Use the same notifier as the hardware mute keybind so the
                // icon and OSD stay consistent whichever control toggles mute.
                Quickshell.execDetached(["prgnotifier", "volume", "toggle"]);
            } else {
                if (parentBar) {
                    parentBar.activePopup = (parentBar.activePopup === root.popupName ? "" : root.popupName);
                }
            }
        }

        onWheel: (wheel) => {
            if (!root.sink || !root.sink.audio) return;
            let step = 0.05;
            let current = root.sink.audio.volume;
            let delta = wheel.angleDelta.y > 0 ? step : -step;
            root.sink.audio.volume = Math.max(0.0, Math.min(1.0, current + delta));
        }
    }
}
