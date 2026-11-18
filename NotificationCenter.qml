import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications

// Owns org.freedesktop.Notifications for the session and renders the cards.
// Stop any external notification daemon before launching Quickshell.
Item {
    id: root

    property bool doNotDisturb: Config.notificationsDoNotDisturb
    property bool enabled: Config.notificationsEnabled
    readonly property var notifications: server.trackedNotifications
    readonly property int count: server.trackedNotifications.count

    onDoNotDisturbChanged: Config.set("notificationsDoNotDisturb", doNotDisturb)
    onEnabledChanged: Config.set("notificationsEnabled", enabled)

    function dismissAll() {
        const items = server.trackedNotifications.values;
        for (let i = items.length - 1; i >= 0; i--) {
            if (items[i]) items[i].dismiss();
        }
    }

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        bodyImagesSupported: true
        actionsSupported: true
        actionIconsSupported: true
        persistenceSupported: true
        onNotification: notification => {
            if (!root.enabled || root.doNotDisturb) {
                notification.dismiss();
                return;
            }
            notification.tracked = true;
        }
    }

    PanelWindow {
        id: notificationWindow

        screen: {
            const focused = Hyprland.focusedMonitor;
            if (focused) {
                for (let i = 0; i < Quickshell.screens.length; i++)
                    if (Quickshell.screens[i].name === focused.name) return Quickshell.screens[i];
            }
            return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
        }
        // Match the supplied SwayNC layout: notifications appear bottom-centre.
        anchors { bottom: true; left: true }
        margins {
            bottom: 15
            left: screen ? Math.max(6, Math.round((screen.width - implicitWidth) / 2)) : 6
        }
        implicitWidth: 320
        implicitHeight: Math.min(4, root.count) * 108 + 8
        visible: root.enabled && !root.doNotDisturb && root.count > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region { item: notificationList }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        ListView {
            id: notificationList
            anchors.fill: parent
            spacing: 8
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.notifications
            add: Transition {
                NumberAnimation {
                    properties: "opacity,scale"
                    from: 0; to: 1
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
            remove: Transition {
                NumberAnimation {
                    properties: "opacity,scale"
                    to: 0
                    duration: 110
                    easing.type: Easing.InCubic
                }
            }
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var notification: modelData
                width: ListView.view.width
                height: Math.max(92, cardContent.implicitHeight + 20)
                radius: Theme.popupRadius
                color: Theme.surface
                border.width: 1
                border.color: notification.urgency === NotificationUrgency.Critical ? Theme.error : Theme.outline_variant

                // Match the supplied SwayNC timing: low 3s, normal 5s,
                // critical stays until dismissed. Honour explicit app timeouts.
                Timer {
                    interval: card.notification.expireTimeout > 0
                              ? Math.round(card.notification.expireTimeout * 1000)
                              : (card.notification.expireTimeout === 0 || card.notification.urgency === NotificationUrgency.Critical
                                 ? 0 : (card.notification.urgency === NotificationUrgency.Low ? 3000 : 5000))
                    running: interval > 0
                    repeat: false
                    onTriggered: card.notification.expire()
                }

                RowLayout {
                    id: cardContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Text {
                        Layout.preferredWidth: 24
                        Layout.alignment: Qt.AlignTop
                        text: card.notification.urgency === NotificationUrgency.Critical ? "󰀦" : "󰂚"
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                        color: card.notification.urgency === NotificationUrgency.Critical ? Theme.error : Theme.primary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: card.notification.appName || "Notification"
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: Theme.on_surface_variant
                            }
                            Text {
                                text: "×"
                                font.family: Theme.fontFamily
                                font.pixelSize: 18
                                color: Theme.on_surface_variant
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: card.notification.dismiss()
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.notification.summary || ""
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            color: Theme.foreground
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: (card.notification.body || "").length > 0
                            text: card.notification.body || ""
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.on_surface_variant
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: card.notification.actions && card.notification.actions.length > 0
                            Repeater {
                                model: card.notification.actions || []
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitWidth: actionLabel.implicitWidth + 18
                                    implicitHeight: 26
                                    radius: 4
                                    color: Theme.surface_variant
                                    border.width: 1
                                    border.color: Theme.outline_variant
                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: modelData.text || "Open"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.primary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.invoke()
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
