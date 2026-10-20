pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var output
    required property var shell
    Component.onCompleted: WidgetLayouts.setTransition(output.name, wallpaperTransition)
    Component.onDestruction: {
        WidgetLayouts.setTransition(output.name, null);
        if (Wallpapers.targetOutput === output.name) Wallpapers.cancel();
        if (ScreenShaders.targetOutput === output.name) ScreenShaders.cancel();
        if (root.shell.shortcutsOutput === output.name) root.shell.shortcutsOutput = "";
    }

    PanelWindow {
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "shoji-shell"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        surfaceFormat.opaque: false
        color: LiveWallpapers.activeOn(root.output.name) ? "transparent" : "#454545"
        mask: Region {}
        WallpaperTransition {
            id: wallpaperTransition
            anchors.fill: parent
            outputName: root.output.name
            visible: !LiveWallpapers.activeOn(root.output.name)
        }
    }
    // The compositor samples wallpaper pixels here; widgets remain above the wave.
    PanelWindow {
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "shoji-wallpaper-wave"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        mask: Region {}
    }
    PanelWindow {
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "shoji-shell"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        mask: Region {
            item: weatherLoader.item ? weatherLoader.item.attributionItem : null
            Region { item: githubLoader.active && githubLoader.enabled ? githubLoader : null }
            Region { item: deepseekLoader.active && deepseekLoader.enabled ? deepseekLoader : null }
            Region { item: activityLoader.active && activityLoader.enabled ? activityLoader : null }
            Region { item: profileLoader.active && profileLoader.enabled ? profileLoader : null }
            Region { item: sessionsLoader.active && sessionsLoader.enabled ? sessionsLoader : null }
            Region { item: nekoLoader.active && nekoLoader.enabled ? nekoLoader : null }
            Region { item: homeLoader.active && homeLoader.enabled ? homeLoader : null }
            Region { item: musicLoader.active && musicLoader.enabled && musicLoader.item ? musicLoader.item.controlsItem : null }
        }
        WidgetWaveLoader {
            id: homeLoader
            widgetId: "home"; output: root.output; transition: wallpaperTransition
            sourceComponent: HomeZone { shell: root.shell; output: root.output }
            // Keep the composition inside the usable desktop on smaller outputs.
            scale: Math.min(1, (root.output.width - 32) / 852, (root.output.height - 152) / 690)
            transformOrigin: custom ? Item.TopLeft : Item.Center
        }
        WidgetWaveLoader {
            id: gamingHomeLoader
            widgetId: "gaming-home"; output: root.output; transition: wallpaperTransition
            sourceComponent: GamingHomeZone { shell: root.shell }
            scale: Math.max(0, Math.min(1, (root.output.width - 32) / 1468, (root.output.height - 152) / 420))
            transformOrigin: custom ? Item.TopLeft : Item.Center
        }
        WidgetWaveLoader {
            id: activityLoader
            widgetId: "activity"; output: root.output; transition: wallpaperTransition
            readonly property bool combined: !custom && placement.vertical === "top"
            fits: !combined || (root.output.width >= 1132 && root.output.height >= 1020)
            scale: combined ? 1 : Math.max(0, Math.min(1, (root.output.width - 32) / 420, (root.output.height - 152) / 630))
            transformOrigin: custom ? Item.TopLeft : Item.Center
            sourceComponent: ActivityWidget {}
        }
        WidgetWaveLoader {
            id: limitsLoader
            widgetId: "limits"; output: root.output; transition: wallpaperTransition
            sourceComponent: AiLimitsWidget {}
        }
        WidgetWaveLoader {
            id: musicLoader
            widgetId: "music"; output: root.output; transition: wallpaperTransition
            y: !custom && placement.above === "limits" ? limitsLoader.y - height - placement.y
                : positionY()
            sourceComponent: MusicWidget {
                id: desktopPlayer
                Component.onCompleted: root.shell.desktopMusic = desktopPlayer
                Component.onDestruction: { if (root.shell.desktopMusic === desktopPlayer) root.shell.desktopMusic = null; }
            }
        }
        WidgetWaveLoader {
            id: weatherLoader
            widgetId: "weather"; output: root.output; transition: wallpaperTransition
            legacyWeather: true
            sourceComponent: WeatherWidget {}
        }
        WidgetWaveLoader {
            id: deepseekLoader
            widgetId: "deepseek"; output: root.output; transition: wallpaperTransition
            sourceComponent: DeepSeekWidget {}
        }
        WidgetWaveLoader {
            id: githubLoader
            widgetId: "github"; output: root.output; transition: wallpaperTransition
            sourceComponent: GithubWidget {}
        }
        WidgetWaveLoader {
            id: sessionsLoader
            widgetId: "sessions"; output: root.output; transition: wallpaperTransition
            y: !custom && placement.vertical === "center"
                ? (limitsLoader.y + limitsLoader.height + deepseekLoader.y - height) / 2
                : positionY()
            sourceComponent: SessionResumeWidget {}
        }
        WidgetWaveLoader {
            id: profileLoader
            widgetId: "profile"; output: root.output; transition: wallpaperTransition
            // Default's neighbours keep their old anchors while another preset fades in.
            readonly property real gapTop: WidgetLayouts.verticalPosition(WidgetLayouts.placement("github", "default"), root.output.height, githubLoader.height) + githubLoader.height + 12
            readonly property real gapBottom: WidgetLayouts.verticalPosition(WidgetLayouts.placement("music", "default"), root.output.height, musicLoader.height) - 12
            readonly property real availableHeight: Math.max(0, gapBottom - gapTop)
            height: custom ? (item ? item.implicitHeight : 0) : Math.min(item ? item.implicitHeight : 0, availableHeight)
            y: custom ? positionY() : gapTop + (availableHeight - height) / 2
            fits: custom || availableHeight >= 180
            sourceComponent: ProfileWidget {}
        }
        WidgetWaveLoader {
            id: nekoLoader
            widgetId: "neko"; output: root.output; transition: wallpaperTransition
            readonly property real availableWidth: Math.max(0, !custom && musicLoader.active ? musicLoader.x - 28 : root.output.width - 32)
            width: Math.max(0, Math.min(210, availableWidth, root.output.height - 84))
            height: width
            x: custom ? positionX() : musicLoader.active ? musicLoader.x - width - 12
                : WidgetLayouts.horizontalPosition(placement, root.output.width, width)
            // Compensate for the transparent margin below the resting paws.
            y: custom ? positionY() : root.output.height - height + height * 0.10 - 8
            fits: width >= 96
            sourceComponent: NekoWidget { musicSource: root.shell.desktopMusic }
        }
    }
    // Rear aquarium plane covers the widgets, while client windows remain above it.
    PanelWindow {
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        visible: ScreenShaders.activeId === "aquarium"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "shoji-aquarium-mist"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        surfaceFormat.opaque: false
        color: "transparent"
        mask: Region {}
    }
    // One shared composition of the windows, beneath the shell controls.
    PanelWindow {
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "shoji-layout-melt"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        mask: Region {}
    }
    PanelWindow {
        id: picker
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        readonly property bool requested: Wallpapers.targetOutput === root.output.name
        visible: requested && pickerLoader.status === Loader.Ready && !!pickerLoader.item
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shoji-shell"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        onVisibleChanged: { if (visible) pickerLoader.forceActiveFocus(); }
        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Wallpapers.cancel()
            Loader {
                id: pickerLoader
                anchors.fill: parent
                focus: true
                active: picker.requested
                sourceComponent: WallpaperPicker { outputName: root.output.name }
                onStatusChanged: {
                    if (status === Loader.Error) {
                        Wallpapers.error = "Не удалось открыть меню обоев. Ввод освобождён.";
                        Wallpapers.cancel();
                    }
                }
            }
        }
        Timer {
            interval: 3000
            running: picker.requested && pickerLoader.status !== Loader.Ready
            onTriggered: Wallpapers.cancel()
        }
    }
    PanelWindow {
        id: shaderPicker
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        readonly property bool requested: ScreenShaders.targetOutput === root.output.name
        visible: requested && ScreenShaders.thumbnailsReady && shaderPickerLoader.status === Loader.Ready && !!shaderPickerLoader.item
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shoji-shader-picker"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        surfaceFormat.opaque: false
        color: "transparent"
        onVisibleChanged: { if (visible) shaderPickerLoader.forceActiveFocus(); }
        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: ScreenShaders.cancel()
            Loader {
                id: shaderPickerLoader
                anchors.fill: parent
                focus: true
                active: shaderPicker.requested
                sourceComponent: ShaderPicker {}
                onStatusChanged: {
                    if (status === Loader.Error) {
                        console.warn("Could not load the screen shader picker");
                        ScreenShaders.cancel();
                    }
                }
            }
        }
        Timer {
            interval: 3000
            running: shaderPicker.requested && shaderPickerLoader.status !== Loader.Ready
            onTriggered: ScreenShaders.cancel()
        }
    }
    PanelWindow {
        id: windowSwitcher
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        readonly property bool requested: Switcher.open && Switcher.targetOutput === root.output.name
        visible: requested && switcherLoader.status === Loader.Ready && !!switcherLoader.item
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shoji-switcher"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        surfaceFormat.opaque: false
        color: "transparent"
        onVisibleChanged: { if (visible) switcherLoader.forceActiveFocus(); }
        Loader {
            id: switcherLoader
            anchors.fill: parent
            focus: true
            active: windowSwitcher.requested
            sourceComponent: WindowSwitcher {}
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.warn("Could not load the window switcher");
                    Switcher.cancel();
                }
            }
        }
        Timer {
            interval: 3000
            running: windowSwitcher.requested && switcherLoader.status !== Loader.Ready
            onTriggered: Switcher.cancel()
        }
    }
    PanelWindow {
        id: shortcutsWindow
        screen: root.output
        anchors { top: true; bottom: true; left: true; right: true }
        readonly property bool requested: root.shell.shortcutsOutput === root.output.name
        visible: requested && shortcutsLoader.status === Loader.Ready && !!shortcutsLoader.item
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shoji-shortcuts"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        onVisibleChanged: { if (visible) shortcutsLoader.forceActiveFocus(); }
        Component {
            id: listComponent
            Shortcuts { onCloseRequested: root.shell.shortcutsOutput = "" }
        }
        Component {
            id: managerComponent
            ShortcutManager { onCloseRequested: root.shell.shortcutsOutput = "" }
        }
        Loader {
            id: shortcutsLoader
            anchors.fill: parent
            focus: true
            active: shortcutsWindow.requested
            sourceComponent: root.shell.shortcutManagerOpen ? managerComponent : listComponent
            onStatusChanged: {
                if (status === Loader.Error) {
                    console.warn("Could not load the shortcuts window");
                    root.shell.shortcutsOutput = "";
                }
            }
        }
        Timer {
            interval: 3000
            running: shortcutsWindow.requested && shortcutsLoader.status !== Loader.Ready
            onTriggered: root.shell.shortcutsOutput = ""
        }
    }
}
