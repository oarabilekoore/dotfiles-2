import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property string dictationText: ""
    property bool isActive: false

    visible: isActive
    height: Theme.barHeight
    width: visible ? (dictLabel.implicitWidth + 12) : 0
    color: "transparent"

    FileView {
        id: dictFile
        path: "/tmp/dictation_state.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.updateState(text())
        Component.onCompleted: {
            let t = text();
            if (t) root.updateState(t);
        }
    }

    function updateState(txt) {
        if (!txt || txt.trim() === "") {
            root.isActive = false;
            return;
        }
        try {
            let d = JSON.parse(txt);
            root.dictationText = d.text || "";
            root.isActive = (root.dictationText.length > 0);
        } catch (e) {
            root.dictationText = txt.trim();
            root.isActive = (root.dictationText.length > 0);
        }
    }

    Text {
        id: dictLabel
        anchors.centerIn: parent
        text: root.dictationText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        color: Theme.primary
    }
}
