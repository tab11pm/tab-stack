pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        PanelIcon { name: "battery"; tint: Power.percentage <= 15 ? Theme.danger : Theme.accent; implicitWidth: 28; implicitHeight: 28 }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 3
            UiText { text: Power.state; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 12 }
            UiText { text: Power.timeLabel; visible: text !== ""; color: Theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
        }
        UiText { text: Power.present ? Power.percentage + "%" : "—"; font.pixelSize: 24; font.weight: Font.DemiBold }
    }
    Meter { Layout.fillWidth: true; label: "Заряд"; reading: Power.present ? Power.percentage + "%" : "—"; fraction: Power.present ? Power.battery.percentage : 0 }
    UiText {
        Layout.fillWidth: true; visible: Power.present && Power.battery.healthSupported
        text: Power.present ? "Состояние батареи: " + Math.round(Power.battery.healthPercentage * 100) + "% от исходной ёмкости" : ""
        color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap
    }
    UiText { text: "Режим производительности"; color: Theme.muted; font.pixelSize: 11; Layout.topMargin: 4 }
    RowLayout {
        Layout.fillWidth: true; spacing: 6
        Repeater {
            model: Power.profiles
            ActionButton {
                required property string modelData
                Layout.fillWidth: true; Layout.preferredWidth: 1
                text: Power.label(modelData); font.pixelSize: 11; padding: 8
                hint: modelData === "power-saver" ? "Энергосбережение" : modelData === "balanced" ? "Сбалансированный режим" : "Максимальная производительность"
                highlighted: Power.activeProfile === modelData
                enabled: !Power.busy
                onClicked: Power.setProfile(modelData)
            }
        }
    }
    UiText { text: Power.error; visible: text !== ""; color: Theme.danger; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
}
