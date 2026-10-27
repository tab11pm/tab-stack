pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "SwitcherInput" as Native

// The Alt+Tab overlay: a horizontal MRU stack of window cards, newest in front.
// Built per output and mounted from WallpaperScreen; the state lives in the
// Switcher singleton. Navigation is driven by the compositor (switcher.next /
// switcher.previous) and by the keys handled here, Enter/Alt-release/click
// commit, Escape cancels.
FocusScope {
    id: root
    focus: true
    readonly property var inputWindow: root.Window.window
    onInputWindowChanged: Native.InputState.watch(inputWindow)
    Component.onDestruction: Native.InputState.unwatch(inputWindow)
    Connections {
        target: Native.InputState
        function onAltReleased(): void { Switcher.commit(); }
    }

    readonly property real expandedWidth: Math.min(320, width * 0.22)
    readonly property real collapsedWidth: Math.min(196, width * 0.13)
    readonly property real cardHeight: Math.min(232, height * 0.36)
    readonly property var selectedEntry:
        (Switcher.index >= 0 && Switcher.index < Switcher.entries.length)
            ? Switcher.entries[Switcher.index] : null

    function ageLabel(ms) {
        if (!ms) return "ранее";
        const s = Math.max(0, (Date.now() - ms) / 1000);
        if (s < 60) return Math.round(s) + " с назад";
        const m = s / 60;
        if (m < 60) return Math.round(m) + " мин назад";
        return Math.round(m / 60) + " ч назад";
    }

    Component.onCompleted: {
        forceActiveFocus();
        Native.InputState.watch(inputWindow);
    }
    Keys.onEscapePressed: Switcher.cancel()
    Keys.onReturnPressed: Switcher.commit()
    Keys.onEnterPressed: Switcher.commit()
    Keys.onTabPressed: Switcher.step(1)
    Keys.onBacktabPressed: Switcher.step(-1)
    Keys.onDownPressed: Switcher.step(1)
    Keys.onUpPressed: Switcher.step(-1)
    Keys.onRightPressed: Switcher.step(1)
    Keys.onLeftPressed: Switcher.step(-1)
    Keys.onReleased: event => { if (event.key === Qt.Key_Alt) Switcher.commit(); }

    Rectangle { anchors.fill: parent; color: "#b311111b" }

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 16

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ПЕРЕКЛЮЧЕНИЕ ОКОН"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 11
                font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.selectedEntry !== null
                text: root.selectedEntry ? (root.selectedEntry.title || root.selectedEntry.appId) : ""
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: 16
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.width - 160)
                horizontalAlignment: Text.AlignHCenter
            }
        }

        ListView {
            id: carousel
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: root.cardHeight + 48
            orientation: ListView.Horizontal
            model: Switcher.entries
            spacing: 20
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            snapMode: ListView.SnapToItem
            preferredHighlightBegin: (width - root.expandedWidth) / 2
            preferredHighlightEnd: preferredHighlightBegin + root.expandedWidth
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 170
            currentIndex: Switcher.index
            onCurrentIndexChanged: Qt.callLater(centerSelection)
            onCountChanged: Qt.callLater(centerSelection)
            onWidthChanged: Qt.callLater(centerSelection)
            function centerSelection() {
                if (currentIndex >= 0 && count)
                    positionViewAtIndex(currentIndex, ListView.Center);
            }
            Component.onCompleted: Qt.callLater(centerSelection)

            delegate: Item {
                id: card
                required property int index
                required property var modelData
                readonly property bool selected: ListView.isCurrentItem
                width: root.expandedWidth
                height: carousel.height

                Item {
                    anchors.centerIn: parent
                    width: card.selected ? root.expandedWidth : root.collapsedWidth
                    height: root.cardHeight
                    Behavior on width { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: Theme.surface
                        border.width: card.selected ? 2 : 1
                        border.color: card.selected ? Theme.accent : Theme.line
                    }
                    Image {
                        anchors { top: parent.top; topMargin: 24; horizontalCenter: parent.horizontalCenter }
                        source: Dock.iconFor(Dock.lookup(card.modelData.appId), card.modelData.appId)
                        sourceSize { width: 52; height: 52 }
                        width: 52; height: 52
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Text {
                        anchors { top: parent.top; topMargin: 96; left: parent.left; right: parent.right; margins: 14 }
                        text: card.modelData.title || card.modelData.appId
                        color: Theme.ink
                        font.family: Theme.font
                        font.pixelSize: card.selected ? 14 : 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Column {
                        anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Рабочий стол " + card.modelData.workspace
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.ageLabel(card.modelData.lastFocusedAt)
                            color: card.modelData.focused ? Theme.accent : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Switcher.pick(card.index)
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Tab — дальше  ·  отпусти Alt — переключить  ·  Esc — отмена"
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 11
        }
    }
}
