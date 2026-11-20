import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io
import ".."

PopupBase {
    id: root

    popupName: "volume"
    implicitWidth: 320
    implicitHeight: volLayout.implicitHeight + 28

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // Bind the default nodes so sink.audio / source.audio report the real volume and mute state.
    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    Process {
        id: pulseMixerProc
        command: ["ghostty", "--class", "floating", "-e", "pulsemixer"]
        onExited: running = false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        border.color: Theme.outline_variant
        border.width: 1
        radius: Theme.popupRadius

        ColumnLayout {
            id: volLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 14

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 18
                    color: Theme.primary
                }
                Text {
                    text: "Audio Settings"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    color: Theme.foreground
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.outline_variant
            }

            // --- OUTPUT SECTION ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "OUTPUT"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.on_surface_variant
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (root.sink && root.sink.description) ? root.sink.description : "Default Output"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.outline
                        elide: Text.ElideRight
                        Layout.maximumWidth: 180
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Mute Button
                    Rectangle {
                        width: 28
                        height: 28
                        radius: 4
                        color: muteOutMouse.containsMouse ? Theme.surface_variant : "transparent"
                        border.color: Theme.outline_variant
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: (root.sink && root.sink.audio && root.sink.audio.muted) ? "" : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            color: (root.sink && root.sink.audio && root.sink.audio.muted) ? Theme.color7 : Theme.foreground
                        }

                        MouseArea {
                            id: muteOutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.sink && root.sink.audio) {
                                    root.sink.audio.muted = !root.sink.audio.muted;
                                }
                            }
                        }
                    }

                    // Slider Track
                    Rectangle {
                        id: outSlider
                        Layout.fillWidth: true
                        height: 20
                        color: "transparent"

                        readonly property real currentVol: (root.sink && root.sink.audio) ? root.sink.audio.volume : 0.0

                        // Track Background
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Theme.surface_variant

                            // Filled Accent Bar
                            Rectangle {
                                width: Math.max(0, Math.min(parent.width, parent.width * outSlider.currentVol))
                                height: parent.height
                                radius: 3
                                color: (root.sink && root.sink.audio && root.sink.audio.muted) ? Theme.color7 : Theme.primary
                            }
                        }

                        // Knob
                        Rectangle {
                            x: Math.max(0, Math.min(parent.width - width, parent.width * outSlider.currentVol - (width / 2)))
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 14
                            radius: 7
                            color: Theme.foreground
                            border.color: Theme.outline
                            border.width: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function setVol(mouse) {
                                if (!root.sink || !root.sink.audio) return;
                                let ratio = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                root.sink.audio.volume = ratio;
                            }
                            onPressed: (mouse) => setVol(mouse)
                            onPositionChanged: (mouse) => {
                                if (pressed) setVol(mouse);
                            }
                        }
                    }

                    // Volume percentage text
                    Text {
                        text: Math.round(((root.sink && root.sink.audio) ? root.sink.audio.volume : 0) * 100) + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.foreground
                        Layout.minimumWidth: 36
                    }
                }
            }

            // --- INPUT SECTION (MICROPHONE) ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "INPUT (MICROPHONE)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.on_surface_variant
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (root.source && root.source.description) ? root.source.description : "Default Input"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.outline
                        elide: Text.ElideRight
                        Layout.maximumWidth: 180
                    }
                }

                // Use the same tested drag-control as the quick-settings sliders.
                // This keeps the microphone knob responsive across PipeWire devices.
                QsSlider {
                    glyph: (root.source && root.source.audio && root.source.audio.muted) ? "󰍭" : "󰍬"
                    value: (root.source && root.source.audio) ? root.source.audio.volume : 0
                    muted: !!root.source && !!root.source.audio && root.source.audio.muted
                    onMoved: (v) => {
                        if (!root.source || !root.source.audio) return;
                        if (v > 0) root.source.audio.muted = false;
                        root.source.audio.volume = v;
                    }
                    onGlyphClicked: {
                        if (!root.source || !root.source.audio) return;
                        root.source.audio.muted = !root.source.audio.muted;
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.outline_variant
            }

            // Footer Button: Audio Mixer (pulsemixer)
            Rectangle {
                Layout.fillWidth: true
                height: 28
                radius: 4
                color: pmMouse.containsMouse ? Theme.surface_variant : "transparent"
                border.color: Theme.outline_variant
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "󰓃"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.primary
                    }
                    Text {
                        text: "Open Audio Mixer (pulsemixer)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.foreground
                    }
                }

                MouseArea {
                    id: pmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        pulseMixerProc.running = false;
                        pulseMixerProc.running = true;
                        root.dismiss();
                    }
                }
            }
        }
    }
}
