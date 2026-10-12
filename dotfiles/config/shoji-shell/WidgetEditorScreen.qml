pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var output
    PanelWindow {
        id: window
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        readonly property bool requested: WidgetEditor.targetOutput === root.output.name
        visible: requested && editorLoader.status === Loader.Ready
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shoji-shell"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        FocusScope {
            id: surface
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: WidgetEditor.cancel()
            Loader {
                id: editorLoader
                anchors.fill: parent
                active: window.requested
                sourceComponent: Item {
                    WidgetLayoutEditor {
                        id: editor
                        parent: surface
                        Component.onCompleted: edit(Wallpapers.layoutId)
                        onClosed: WidgetEditor.cancel()
                    }
                }
                onStatusChanged: {
                    if (status === Loader.Error) {
                        console.warn("Could not open the widget layout editor");
                        WidgetEditor.cancel();
                    }
                }
            }
        }
    }
}
