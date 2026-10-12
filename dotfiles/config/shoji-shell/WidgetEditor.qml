pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Singleton {
    id: root
    property string targetOutput: ""
    property var screenNames: Quickshell.screens.map(screen => screen.name)
    readonly property bool busy: CustomWidgetLayout.saving || Wallpapers.saving || LiveWallpapers.busy
    function toggle(outputName) {
        if (busy) return;
        if (targetOutput !== "") { cancel(); return; }
        if (!CustomWidgetLayout.ready) return;
        const name = screenNames.includes(outputName) ? outputName
            : screenNames.includes(WidgetLayouts.primaryOutputName) ? WidgetLayouts.primaryOutputName : screenNames[0];
        if (!name) return;
        Wallpapers.cancel();
        ScreenShaders.cancel();
        targetOutput = name;
    }
    function cancel() { if (!busy) targetOutput = ""; }
    function checkOutput() {
        if (!busy && targetOutput !== "" && !screenNames.includes(targetOutput)) targetOutput = "";
    }
    onScreenNamesChanged: checkOutput()
    onBusyChanged: checkOutput()
}
