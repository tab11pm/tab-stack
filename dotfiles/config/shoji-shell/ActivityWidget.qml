pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

WidgetSurface {
    id: root
    implicitWidth: 420
    implicitHeight: 630
    readonly property var statistics: Activity.report
    function duration(seconds) {
        const minutes = Math.floor((seconds || 0) / 60);
        return Math.floor(minutes / 60) + " ч " + minutes % 60 + " мин";
    }
    function selectedDay() {
        const pieces = Activity.selectedDate.split("-");
        return new Date(Number(pieces[0]), Number(pieces[1]) - 1, Number(pieces[2]), 12);
    }
    function move(amount) {
        const day = selectedDay();
        day.setDate(day.getDate() + amount * (Activity.period === "week" ? 7 : 1));
        const today = new Date(); today.setHours(12, 0, 0, 0);
        if (day > today) day.setTime(today.getTime());
        Activity.selectPeriod(Qt.formatDate(day, "yyyy-MM-dd"), Activity.period);
    }
    function periodLabel() {
        const day = selectedDay();
        if (Activity.period === "day") return day.toLocaleDateString(Qt.locale("ru_RU"), "d MMMM yyyy");
        day.setDate(day.getDate() - (day.getDay() + 6) % 7);
        const end = new Date(day); end.setDate(day.getDate() + 6);
        return day.toLocaleDateString(Qt.locale("ru_RU"), "d MMM") + " — " + end.toLocaleDateString(Qt.locale("ru_RU"), "d MMM yyyy");
    }
    function canMoveForward() {
        const day = selectedDay();
        const today = new Date(); today.setHours(12, 0, 0, 0);
        if (Activity.period === "week") {
            day.setDate(day.getDate() - (day.getDay() + 6) % 7);
            today.setDate(today.getDate() - (today.getDay() + 6) % 7);
        }
        return day < today;
    }
    function entry(appId) { return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId); }
    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            UiText { text: "Время за ПК"; font.pixelSize: 18; font.weight: Font.DemiBold; Layout.fillWidth: true }
            UiText { text: "Super+Ctrl+T"; font.pixelSize: 11; color: Theme.muted }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 56
            color: Theme.raised; radius: 10
            RowLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 10
                Rectangle { implicitWidth: 7; implicitHeight: 7; radius: 4; color: Activity.tracking ? "#a6e3a1" : Theme.muted }
                UiText {
                    Layout.fillWidth: true
                    text: Activity.error || Activity.status
                    color: Activity.error ? Theme.danger : Theme.ink
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Button {
                    id: toggle
                    text: Activity.manualPaused ? "Я вернулся" : "Я отошёл"
                    enabled: Activity.loaded
                    Accessible.name: "Переключить учёт времени: " + text
                    onClicked: Activity.toggle()
                    background: Rectangle { radius: 8; color: toggle.hovered ? Theme.hover : Theme.surface; border.width: 1; border.color: Theme.line }
                    contentItem: UiText { text: toggle.text; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{title:"День", key:"day"}, {title:"Неделя", key:"week"}]
                Button {
                    id: tab
                    required property var modelData
                    text: modelData.title
                    checked: Activity.period === modelData.key
                    onClicked: Activity.selectPeriod(Activity.selectedDate, modelData.key)
                    background: Rectangle { radius: 8; color: tab.checked ? Theme.accent : tab.hovered ? Theme.hover : Theme.raised }
                    contentItem: UiText { text: tab.text; font.pixelSize: 12; color: tab.checked ? Theme.surface : Theme.ink; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
            Item { Layout.fillWidth: true }
            Button {
                text: "Сегодня"
                onClicked: Activity.selectPeriod(Qt.formatDate(new Date(), "yyyy-MM-dd"), Activity.period)
                background: Rectangle { radius: 8; color: Theme.raised }
                contentItem: UiText { text: "Сегодня"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Button {
                id: previous
                text: "‹"; implicitWidth: 30; implicitHeight: 28
                Accessible.name: "Предыдущий период"
                onClicked: root.move(-1)
                background: Rectangle { radius: 8; color: previous.hovered ? Theme.hover : Theme.raised }
                contentItem: UiText { text: "‹"; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            UiText { Layout.fillWidth: true; text: root.periodLabel(); horizontalAlignment: Text.AlignHCenter; font.pixelSize: 12 }
            Button {
                id: next
                text: "›"; implicitWidth: 30; implicitHeight: 28
                enabled: root.canMoveForward()
                Accessible.name: "Следующий период"
                onClicked: root.move(1)
                background: Rectangle { radius: 8; color: next.hovered ? Theme.hover : Theme.raised; opacity: next.enabled ? 1 : 0.4 }
                contentItem: UiText { text: "›"; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: next.enabled ? 1 : 0.4 }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            UiText { text: root.duration(root.statistics.totalSeconds); font.pixelSize: 30; font.weight: Font.DemiBold; Layout.fillWidth: true }
            UiText { visible: Activity.period === "week"; text: "В среднем за день\n" + root.duration(root.statistics.averageSeconds); font.pixelSize: 11; color: Theme.muted; horizontalAlignment: Text.AlignRight }
        }
        ActivityChart { Layout.fillWidth: true; Layout.preferredHeight: 112; bars: root.statistics.bars || []; period: Activity.period }
        RowLayout {
            Layout.fillWidth: true
            UiText { text: "Топ приложений"; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
            UiText { text: "Время · доля"; font.pixelSize: 11; color: Theme.muted }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            Repeater {
                model: root.statistics.apps || []
                RowLayout {
                    id: appRow
                    required property var modelData
                    readonly property var desktop: root.entry(modelData.appId)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    spacing: 9
                    Item {
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        Image {
                        id: appIcon
                        anchors.fill: parent
                         source: Quickshell.iconPath(appRow.desktop && appRow.desktop.icon ? appRow.desktop.icon : "application-x-executable", true)
                        sourceSize: Qt.size(44,44)
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 6; color: Theme.raised
                            visible: appIcon.status !== Image.Ready
                            UiText { anchors.centerIn: parent; text: (appRow.desktop ? appRow.desktop.name : appRow.modelData.appId).slice(0, 1).toUpperCase(); font.pixelSize: 11; color: Theme.muted }
                        }
                    }
                    UiText { Layout.fillWidth: true; text: appRow.desktop ? appRow.desktop.name : appRow.modelData.appId; font.pixelSize: 12; elide: Text.ElideRight }
                    UiText { text: root.duration(appRow.modelData.seconds); font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight }
                    UiText { text: Math.round(appRow.modelData.share * 100) + "%"; font.pixelSize: 11; color: Theme.accent; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignRight }
                }
            }
            UiText {
                visible: !root.statistics.apps || root.statistics.apps.length === 0
                Layout.fillWidth: true
                text: Activity.error ? "История временно недоступна" : root.statistics.totalSeconds > 0 ? "В этом периоде нет времени активных приложений" : "Пока нет записей за этот период"
                font.pixelSize: 12; color: Theme.muted
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillHeight: true }
        }
        RowLayout {
            Layout.fillWidth: true
            Button {
                id: viewingButton
                text: "Просмотр"
                checked: Activity.viewing
                enabled: Activity.loaded
                Accessible.name: "Просмотр: " + (Activity.viewing ? "включён" : "выключен")
                onClicked: Activity.toggleViewing()
                background: Rectangle { radius: 8; color: viewingButton.checked ? Theme.accent : viewingButton.hovered ? Theme.hover : Theme.raised }
                contentItem: UiText { text: viewingButton.text; font.pixelSize: 12; color: viewingButton.checked ? Theme.surface : Theme.ink; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            UiText {
                Layout.fillWidth: true
                text: Activity.viewing ? (Activity.manualPaused ? "Просмотр включён · ручная пауза" : "Без автопаузы и автосна") : "Для фильмов и чтения"
                font.pixelSize: 11; color: Theme.muted; wrapMode: Text.WordWrap
            }
        }
        UiText {
            Layout.fillWidth: true
            text: Activity.viewing ? "Просмотр не снимает ручную паузу.\nПосле просмотра выключите этот режим." : "Автопауза через 5 минут без действий.\nПервые 5 минут учитываются; ввод снимает автопаузу."
            font.pixelSize: 10; color: Theme.muted
            wrapMode: Text.WordWrap
        }
    }
}
