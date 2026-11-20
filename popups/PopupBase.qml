import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

// Shared popup shell: placed under a bar module, takes keyboard focus, and dismisses
// itself when you click anywhere outside it (or the bar).
//
// This is a layer-shell PanelWindow rather than a PopupWindow. HyprlandFocusGrab only
// recognises real windows / layer surfaces; an xdg_popup is not one, so every click
// *inside* a PopupWindow counted as "outside" and closed it immediately. A layer surface
// with keyboardFocus OnDemand is also what lets TextInputs and toggles receive input.
PanelWindow {
    id: root

    property var parentBar: null
    property var anchorItem: null
    property string popupName: ""
    // Edges.Left  -> popup grows to the left of the module (right edges aligned)
    // Edges.Right -> popup grows to the right of the module (left edges aligned)
    // neither     -> centred under the module
    property int popupGravity: Edges.Bottom | Edges.Left
    // Escape closes the popup. A subclass with its own Escape behaviour (e.g. cancelling a
    // password prompt) binds this to false while that behaviour is active.
    property bool escapeCloses: true

    screen: parentBar ? parentBar.screen : null

    // Sits just above the bottom bar
    anchors {
        top: true
        left: true
    }
    margins.top: parentBar ? parentBar.margins.bottom + parentBar.height + 6
                              : Theme.barMargin + Theme.barHeight + 6
    margins.left: 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-popup"
    // Exclusive while open so the popup reliably receives Escape; the focus grab below
    // still releases it as soon as you click anywhere outside.
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function reposition() {
        if (!anchorItem || !parentBar) return;
        // bar-window coordinates -> screen coordinates (the bar has a left margin)
        const p = anchorItem.mapToItem(null, 0, 0);
        const px = p.x + parentBar.margins.left;
        const screenW = parentBar.width + parentBar.margins.left + parentBar.margins.right;
        let x;
        if (popupGravity & Edges.Left)
            x = px + anchorItem.width - implicitWidth;
        else if (popupGravity & Edges.Right)
            x = px;
        else
            x = px + anchorItem.width / 2 - implicitWidth / 2;
        const maxX = screenW - implicitWidth - 6;
        margins.left = Math.round(Math.max(6, Math.min(maxX, x)));
    }

    onVisibleChanged: if (visible) reposition()
    onAnchorItemChanged: if (visible) reposition()
    onImplicitWidthChanged: if (visible) reposition()
    Component.onCompleted: if (visible) reposition()

    function dismiss() {
        if (root.parentBar && root.parentBar.activePopup === root.popupName)
            root.parentBar.activePopup = "";
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible && root.escapeCloses
        onActivated: root.dismiss()
    }

    // Clicks inside the popup or on the bar are kept; anything else clears the grab.
    HyprlandFocusGrab {
        windows: root.parentBar ? [root, root.parentBar] : [root]
        active: root.visible
        onCleared: root.dismiss()
    }
}
