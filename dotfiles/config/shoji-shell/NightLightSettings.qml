pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "NightLightSchedule.js" as Schedule

Rectangle {
    id: card
    property bool expanded: false
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 24
    radius: 8
    color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.035)
    border.width: 1; border.color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.07)
    ColumnLayout {
        id: content
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                UiText { text: "Ночной режим"; font.weight: Font.Medium; Layout.fillWidth: true }
                UiText { text: NightLight.status + " · " + NightLight.details; color: Theme.muted; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            ActionButton {
                text: NightLight.applied ? "Выключить" : "Включить"
                highlighted: NightLight.applied
                enabled: NightLight.ready && NightLight.loaded
                hint: "Включить или выключить тёплый ночной фильтр"
                onClicked: NightLight.toggle()
            }
            ActionButton {
                text: card.expanded ? "⌃" : "⌄"; hint: "Настройки ночного режима"
                onClicked: card.expanded = !card.expanded
            }
        }
        ColumnLayout {
            visible: card.expanded; Layout.fillWidth: true; spacing: 8
            RowLayout {
                Layout.fillWidth: true
                UiText { text: "По расписанию"; Layout.fillWidth: true }
                ActionButton {
                    text: NightLight.config.scheduled ? "Вкл" : "Выкл"
                    highlighted: NightLight.config.scheduled; enabled: NightLight.loaded
                    hint: "Автоматическое включение ночного режима по времени"
                    onClicked: NightLight.setSchedule(!NightLight.config.scheduled)
                }
            }
            RowLayout {
                visible: NightLight.config.scheduled; Layout.fillWidth: true
                UiText { text: "С"; color: Theme.muted }
                TextField {
                    id: startTime
                    Layout.fillWidth: true; Layout.minimumWidth: 65
                    text: NightLight.config.start; placeholderText: "22:00"
                    maximumLength: 5; color: Theme.ink; font.family: Theme.font
                    Accessible.name: "Время включения ночного режима, часы и минуты"
                    background: Rectangle { radius: 8; color: Theme.raised; border.color: startTime.activeFocus ? Theme.accent : Theme.line }
                }
                UiText { text: "До"; color: Theme.muted }
                TextField {
                    id: endTime
                    Layout.fillWidth: true; Layout.minimumWidth: 65
                    text: NightLight.config.end; placeholderText: "07:00"
                    maximumLength: 5; color: Theme.ink; font.family: Theme.font
                    Accessible.name: "Время выключения ночного режима, часы и минуты"
                    background: Rectangle { radius: 8; color: Theme.raised; border.color: endTime.activeFocus ? Theme.accent : Theme.line }
                }
                ActionButton {
                    text: "Сохранить"
                    enabled: Schedule.validTime(startTime.text) && Schedule.validTime(endTime.text)
                        && startTime.text !== endTime.text
                        && (startTime.text !== NightLight.config.start || endTime.text !== NightLight.config.end)
                    onClicked: NightLight.setTimes(startTime.text, endTime.text)
                }
            }
            UiText {
                visible: NightLight.config.scheduled && (!Schedule.validTime(startTime.text)
                    || !Schedule.validTime(endTime.text) || startTime.text === endTime.text)
                text: "Введи разное время в формате ЧЧ:ММ"; color: Theme.danger
                font.pixelSize: 10; Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
                UiText { text: "Теплота цвета"; color: Theme.muted; Layout.fillWidth: true }
                UiText { text: Math.round(warmth.value) + " K"; color: Theme.muted; font.pixelSize: 11 }
            }
            PanelSlider {
                id: warmth
                Layout.fillWidth: true
                from: 2500; to: 6500; stepSize: 100
                value: NightLight.config.temperature
                enabled: NightLight.loaded
                Accessible.name: "Цветовая температура ночного режима"
                onPressedChanged: { if (!pressed && enabled) NightLight.setTemperature(value); }
                Keys.onReleased: event => { if (enabled) NightLight.setTemperature(value); }
            }
            RowLayout {
                Layout.fillWidth: true
                UiText { text: "Теплее"; color: Theme.muted; font.pixelSize: 10; Layout.fillWidth: true }
                UiText { text: "Нейтральнее"; color: Theme.muted; font.pixelSize: 10 }
            }
            ActionButton {
                visible: NightLight.overrideLabel !== ""
                text: "Вернуться к расписанию"; onClicked: NightLight.resumeSchedule()
            }
        }
        UiText {
            text: NightLight.storageError || NightLight.error
            visible: text !== ""; color: Theme.danger; font.pixelSize: 10
            wrapMode: Text.Wrap; Layout.fillWidth: true
        }
    }
}
