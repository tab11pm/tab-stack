pragma ComponentBehavior: Bound
import QtQuick

Loader {
    id: root
    required property string widgetId
    required property var output
    required property var transition
    property bool fits: true
    property bool legacyWeather: false
    readonly property bool beforeVisible: visibleFor(transition.displayedLayout)
    readonly property bool afterVisible: transition.transitioning
        ? visibleFor(transition.transitionLayout) : beforeVisible
    readonly property bool relocating: (transition.preparing || transition.transitioning)
        && WidgetLayouts.changesPlacement(widgetId, output, transition.displayedLayout, transition.transitionLayout)
    readonly property var placementLayout: beforeVisible && !(transition.transitioning && relocating)
        ? transition.displayedLayout : transition.transitionLayout
    readonly property bool custom: WidgetLayouts.isCustom(placementLayout)
    readonly property var placement: legacyWeather && !custom
        ? ({ output: output.name, horizontal: "left", vertical: "bottom", x: 16, y: 16 })
        : WidgetLayouts.placement(widgetId, placementLayout)
    function visibleFor(selected) {
        if (selected.id === "empty") return false;
        return legacyWeather && !WidgetLayouts.isCustom(selected) ? Settings.enabled("weather")
            : WidgetLayouts.enabledOn(widgetId, output, selected);
    }
    function positionX() {
        const size = custom ? width * scale : width;
        const value = WidgetLayouts.horizontalPosition(placement, output.width, size);
        return custom ? Math.max(0, Math.min(Math.max(0, output.width - size), value)) : value;
    }
    function positionY() {
        const size = custom ? height * scale : height;
        const value = WidgetLayouts.verticalPosition(placement, output.height, size);
        return custom ? Math.max(0, Math.min(Math.max(0, output.height - size), value)) : value;
    }
    x: positionX()
    y: positionY()
    active: Wallpapers.ready && transition.hasWallpaper && fits && (beforeVisible || afterVisible)
    enabled: !LiveWallpapers.busy && !transition.preparing
        && !(transition.transitioning && (beforeVisible !== afterVisible || relocating))
    layer.enabled: transition.transitioning || LiveWallpapers.busy
    layer.effect: WidgetWaveMask {
        transitionContext: root.transition
        screenSize: Qt.size(root.output.width, root.output.height)
        localOrigin: Qt.vector2d(root.x, root.y)
        widgetSize: Qt.size(root.width, root.height)
        localProgress: root.transition.progress
        localBefore: root.beforeVisible && !root.relocating ? 1 : 0
        localAfter: root.afterVisible ? 1 : 0
    }
    WidgetWaveSnapshot {
        id: outgoing
        parent: root.parent
        transition: root.transition
        sourceItem: root.item
        moving: root.relocating
        viewportSize: Qt.size(root.output.width, root.output.height)
        captureOrigin: Qt.vector2d(root.x, root.y)
        x: frozenOrigin.x; y: frozenOrigin.y
        width: frozenSize.width; height: frozenSize.height
    }
}
