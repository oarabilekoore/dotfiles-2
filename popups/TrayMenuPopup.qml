import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."

// Right-click menu for system tray items (Steam, Discord, nm-applet, ...), drawn by us
// from the item's dbusmenu instead of Qt's native platform menu, which does not show up
// under layer-shell bars. Supports separators, check/radio items, icons and submenus.
PopupBase {
    id: root

    popupName: "traymenu"
    popupGravity: Edges.Bottom                    // centred under the icon
    implicitWidth: 240
    implicitHeight: Math.min(list.implicitHeight, 460) + 16

    property var stack: []                        // opened submenus, newest last
    readonly property var trayItem: parentBar ? parentBar.trayItem : null
    readonly property var current: stack.length > 0 ? stack[stack.length - 1]
                                   : (trayItem ? trayItem.menu : null)

    onTrayItemChanged: stack = []
    onVisibleChanged: if (!visible) stack = []

    QsMenuOpener {
        id: opener
        menu: root.current
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        border.color: Theme.outline_variant
        border.width: 1
        radius: Theme.popupRadius

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            contentWidth: width
            contentHeight: list.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: list
                width: flick.width
                spacing: 2

                // Back row when inside a submenu
                Rectangle {
                    visible: root.stack.length > 0
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 6
                    color: backMouse.containsMouse ? Theme.alpha(Theme.foreground, 0.10) : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: "‹  Back"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.on_surface_variant
                    }
                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.stack = root.stack.slice(0, -1)
                    }
                }

                Repeater {
                    model: opener.children

                    delegate: Item {
                        id: row
                        required property var modelData
                        readonly property var e: modelData

                        Layout.fillWidth: true
                        implicitHeight: e.isSeparator ? 9 : 30

                        Rectangle {
                            visible: row.e.isSeparator
                            anchors.centerIn: parent
                            width: parent.width - 8
                            height: 1
                            color: Theme.outline_variant
                        }

                        Rectangle {
                            visible: !row.e.isSeparator
                            anchors.fill: parent
                            radius: 6
                            color: (rowMouse.containsMouse && row.e.enabled)
                                   ? Theme.alpha(Theme.foreground, 0.10) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Text {
                                    visible: row.e.buttonType !== QsMenuButtonType.None
                                    Layout.preferredWidth: 14
                                    text: row.e.checkState === Qt.Checked ? "✓" : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.primary
                                }
                                IconImage {
                                    visible: row.e.icon !== ""
                                    implicitSize: 16
                                    source: row.e.icon
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.e.text
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: row.e.enabled ? Theme.foreground : Theme.outline
                                }
                                Text {
                                    visible: row.e.hasChildren
                                    text: "›"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.on_surface_variant
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !row.e.isSeparator && row.e.enabled
                                onClicked: {
                                    if (row.e.hasChildren) {
                                        root.stack = root.stack.concat([row.e]);
                                    } else {
                                        row.e.triggered();
                                        root.dismiss();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
