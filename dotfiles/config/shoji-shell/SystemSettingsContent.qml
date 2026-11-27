pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

FocusScope {
    id: window
    focus: true
    enabled: SystemSettings.opened
    readonly property bool compactNavigation: width < 860
    readonly property bool editable: SystemSettings.available && SystemSettings.loaded && !SystemSettings.busy && !SystemSettings.trial
    readonly property var sections: [
        { id: "displays", title: "Мониторы", icon: "settings-monitor", hint: "экран разрешение масштаб яркость" },
        { id: "keyboard", title: "Клавиатура", icon: "keyboard", hint: "раскладка язык повтор ввод" },
        { id: "pointer", title: "Мышь и тачпад", icon: "settings-mouse", hint: "курсор скорость прокрутка касание" },
        { id: "audio", title: "Звук", icon: "volume", hint: "громкость вывод микрофон" },
        { id: "connections", title: "Подключения", icon: "wifi", hint: "сеть интернет bluetooth wifi" },
        { id: "lock", title: "Блокировка", icon: "settings-lock", hint: "пароль таймер dpms бездействие" },
        { id: "appearance", title: "Обои и рабочий стол", icon: "image", hint: "оформление тема обои виджеты эффекты" },
        { id: "notifications", title: "Уведомления", icon: "bell", hint: "тихий режим история не беспокоить" }
    ]
    property string displayedPage: SystemSettings.page
    readonly property bool fixedPage: displayedPage === "appearance" || displayedPage === "connections"
    readonly property var currentSection: sections.find(s => s.id === displayedPage) || sections[0]
    Component.onCompleted: displayedPage = SystemSettings.page
    property double now: Date.now()
    readonly property int remaining: SystemSettings.trial ? Math.max(0, Math.ceil((SystemSettings.trial.deadline - now) / 1000)) : 0
    Timer { interval: 1000; repeat: true; running: !!SystemSettings.trial; onTriggered: window.now = Date.now() }
    Connections { target: SystemSettings; function onTrialChanged(): void { window.now = Date.now(); } }
    Keys.onEscapePressed: SystemSettings.close()
    Connections {
        target: SystemSettings
        function onPageChanged(): void { pageTransition.restart(); }
    }
    SequentialAnimation {
        id: pageTransition
        NumberAnimation { target: pageHost; property: "opacity"; to: 0; duration: Theme.duration(70) }
        ScriptAction { script: { window.displayedPage = SystemSettings.page; pageHost.offset = 8; } }
        ParallelAnimation {
            NumberAnimation { target: pageHost; property: "opacity"; to: 1; duration: Theme.duration(180); easing.type: Easing.OutCubic }
            NumberAnimation { target: pageHost; property: "offset"; to: 0; duration: Theme.duration(220); easing.type: Easing.OutCubic }
        }
    }

    component Group: Rectangle {
        id: group
        property string heading: ""
        property bool bounded: false
        default property alias content: body.data
        radius: Theme.surfaceRadius
        color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.02)
        border.width: 1
        border.color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.09)
        Layout.fillWidth: true
        implicitHeight: bounded ? 0 : body.implicitHeight + 36
        ColumnLayout {
            id: body
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
            height: group.bounded ? Math.max(0, group.height - 36) : implicitHeight
            spacing: 18
            UiText { text: group.heading; visible: text !== ""; Layout.fillWidth: true; font.pixelSize: 13; font.weight: Font.DemiBold }
        }
    }
    component Range: RowLayout {
        id: range
        property real value: 0
        property real from: 0
        property real to: 1
        property real step: 0.01
        property string suffix: ""
        property string hint: ""
        signal committed(real value)
        implicitWidth: 240
        spacing: 10
        PanelSlider {
            id: slider
            Layout.fillWidth: true
            from: range.from; to: range.to; stepSize: range.step; value: range.value
            Accessible.name: range.hint
            onPressedChanged: { if (!pressed) range.committed(value); }
            onMoved: { if (!pressed) range.committed(value); }
        }
        UiText { text: (range.step >= 1 ? Math.round(slider.value) : slider.value.toFixed(2)) + range.suffix; font.pixelSize: 11; color: Theme.muted; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
    }

    WidgetSurface {
        anchors.fill: parent
        grainAlpha: 0.015
        topLeftRadius: SystemSettings.edge === "left" ? 0 : radius
        bottomLeftRadius: SystemSettings.edge === "left" || SystemSettings.edge === "bottom" ? 0 : radius
        topRightRadius: SystemSettings.edge === "right" ? 0 : radius
        bottomRightRadius: SystemSettings.edge === "right" || SystemSettings.edge === "bottom" ? 0 : radius
        readonly property color backdropColor: Qt.darker(Theme.surface, 1.12)
        color: Qt.rgba(backdropColor.r, backdropColor.g, backdropColor.b, 0.9)
        RowLayout {
            anchors.fill: parent
            spacing: 0
            Rectangle {
                Layout.fillHeight: true; Layout.preferredWidth: window.compactNavigation ? 64 : 216
                color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.015)
                radius: 10
                topLeftRadius: SystemSettings.edge === "left" ? 0 : radius
                bottomLeftRadius: SystemSettings.edge === "left" || SystemSettings.edge === "bottom" ? 0 : radius
                ColumnLayout {
                    anchors { fill: parent; margins: window.compactNavigation ? 10 : 14 }
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 7; Layout.bottomMargin: 14; spacing: 10
                        PanelIcon { name: "home-settings"; tint: Theme.accent }
                        ColumnLayout {
                            visible: !window.compactNavigation
                            spacing: 2
                            UiText { text: "Настройки"; font.pixelSize: 17; font.weight: Font.DemiBold }
                            UiText { text: "Shoji Desktop"; font.pixelSize: 10; color: Theme.muted }
                        }
                    }
                    SettingsField {
                        id: search
                        visible: !window.compactNavigation
                        Layout.fillWidth: true; Layout.bottomMargin: 10
                        placeholderText: "Найти раздел"
                        Accessible.name: "Поиск раздела настроек"
                    }
                    Repeater {
                        model: window.sections
                        DeviceRow {
                            required property var modelData
                            Layout.fillWidth: true
                            text: window.compactNavigation ? "" : modelData.title; glyph: modelData.icon
                            hint: modelData.title
                            selected: SystemSettings.page === modelData.id
                            trailingIcon: ""
                            visible: (modelData.title + " " + modelData.hint).toLowerCase().includes(search.text.trim().toLowerCase())
                            onClicked: SystemSettings.page = modelData.id
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
            Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.08) }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.margins: 24
                spacing: 16
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 5
                        UiText { text: window.currentSection.title; font.pixelSize: 23; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        UiText { text: "Параметры рабочего окружения"; color: Theme.muted; font.pixelSize: 11 }
                    }
                    SettingsActionButton { icon.source: Qt.resolvedUrl("icons/close.svg"); implicitWidth: 34; padding: 8; hint: "Закрыть настройки"; onClicked: SystemSettings.close() }
                }
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: trialContent.implicitHeight + 24
                    radius: 10; visible: !!SystemSettings.trial
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                    ColumnLayout {
                        id: trialContent
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 }
                        spacing: 8
                        UiText { text: "Изображение в порядке? Возврат прежних настроек через " + window.remaining + " с"; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 12 }
                        RowLayout {
                            SettingsActionButton { text: "Оставить"; highlighted: true; enabled: !SystemSettings.busy; onClicked: SystemSettings.confirmDisplays() }
                            SettingsActionButton { text: "Вернуть прежние"; enabled: !SystemSettings.busy; onClicked: SystemSettings.revertDisplays() }
                        }
                    }
                }
                UiText {
                    visible: !SystemSettings.available && ["displays", "keyboard", "pointer"].includes(SystemSettings.page)
                    text: "Параметры ввода и дисплеев станут доступны после подключения модуля настроек в ShojiWM."
                    color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 12
                }
                Item {
                    id: pageHost
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    property real offset: 0
                    transform: Translate { y: pageHost.offset }
                    enabled: !pageTransition.running
                    ScrollView {
                        id: scroll
                        anchors.fill: parent
                        visible: !window.fixedPage
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        Loader {
                            id: pageLoader
                            asynchronous: true
                            active: !window.fixedPage
                            width: scroll.availableWidth
                            sourceComponent: window.displayedPage === "keyboard" ? keyboardPage
                                : window.displayedPage === "pointer" ? pointerPage
                                : window.displayedPage === "audio" ? audioPage
                                : window.displayedPage === "lock" ? lockPage
                                : window.displayedPage === "notifications" ? notificationsPage : displaysPage
                            onSourceComponentChanged: { if (scroll.contentItem) scroll.contentItem.contentY = 0; }
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        asynchronous: true
                        active: window.fixedPage
                        sourceComponent: window.displayedPage === "connections" ? connectionsPage : appearancePage
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    UiText {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 11
                        text: SystemSettings.error || (SystemSettings.busy ? "Сохранение…" : SystemSettings.status)
                        color: SystemSettings.error ? Theme.danger : Theme.muted
                    }
                    SettingsActionButton { text: "Обновить"; implicitHeight: 30; font.pixelSize: 11; enabled: !SystemSettings.busy; onClicked: SystemSettings.refresh() }
                }
            }
        }
    }

    Component {
        id: keyboardPage
        ColumnLayout {
            spacing: 16
            Group {
                heading: "Раскладки"
                enabled: window.editable
                SettingsRow {
                    label: "Языки ввода"
                    description: "Порядок и вариант раскладок"
                    SettingsChoice {
                        hint: "Языки ввода"
                        model: [{ label: "EN + RU · международная", value: "us,ru|,ruintl_ru" }, { label: "EN + RU · стандартная", value: "us,ru|," },
                            { label: "EN", value: "us|" }]
                        currentIndex: model.findIndex(m => m.value === ((SystemSettings.values.keyboard || {}).layout + "|" + (SystemSettings.values.keyboard || {}).variant))
                        onActivated: { const parts = currentValue.split("|"); SystemSettings.updateInput("keyboard", { layout: parts[0], variant: parts[1] }); }
                    }
                }
                SettingsRow {
                    label: "Переключение раскладки"
                    SettingsChoice {
                        hint: "Переключение раскладки"
                        model: [{ label: "Alt + Shift", value: "grp:alt_shift_toggle" }, { label: "Ctrl + Shift", value: "grp:ctrl_shift_toggle" }, { label: "Caps Lock", value: "grp:caps_toggle" }]
                        currentIndex: model.findIndex(m => m.value === (SystemSettings.values.keyboard || {}).options)
                        onActivated: SystemSettings.updateInput("keyboard", { options: currentValue })
                    }
                }
                SettingsRow { label: "Сейчас активна"; description: "Состояние от композитора"; UiText { text: Keyboard.label || "—"; color: Theme.accent } }
            }
            Group {
                heading: "Повтор клавиш"
                enabled: window.editable
                SettingsRow {
                    label: "Скорость повтора"; description: "Символов в секунду при удержании"
                    Range { value: (SystemSettings.values.keyboard || {}).repeatRate || 60; from: 1; to: 100; step: 1; hint: "Скорость повтора"; onCommitted: value => SystemSettings.updateInput("keyboard", { repeatRate: Math.round(value) }) }
                }
                SettingsRow {
                    label: "Задержка повтора"; description: "Пауза перед первым повторением"
                    Range { value: (SystemSettings.values.keyboard || {}).repeatDelay || 250; from: 150; to: 1500; step: 50; suffix: " мс"; hint: "Задержка повтора"; onCommitted: value => SystemSettings.updateInput("keyboard", { repeatDelay: Math.round(value) }) }
                }
            }
            Group {
                heading: "Проверка ввода"
                SettingsField { Layout.fillWidth: true; placeholderText: "Попробуй раскладку и удержание клавиши"; Accessible.name: "Проверка клавиатуры" }
                UiText { text: "Текст из этого поля не сохраняется."; font.pixelSize: 11; color: Theme.muted }
            }
            Group {
                heading: "Подключённые клавиатуры"
                Repeater { model: SystemSettings.devices.filter(d => d.kind.keyboard); UiText { required property var modelData; text: modelData.name; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 12 } }
            }
        }
    }
    Component {
        id: pointerPage
        ColumnLayout {
            spacing: 16
            Group {
                heading: "Мышь"
                enabled: window.editable
                SettingsRow {
                    label: "Скорость указателя"
                    Range { value: (SystemSettings.values.pointer || {}).pointerAccel || 0; from: -1; to: 1; step: 0.05; hint: "Скорость указателя"; onCommitted: value => SystemSettings.updateInput("pointer", { pointerAccel: value }) }
                }
                SettingsRow {
                    label: "Ускорение"
                    SettingsChoice {
                        hint: "Ускорение мыши"
                        model: [{ label: "Постоянная скорость", value: "flat" }, { label: "Адаптивное", value: "adaptive" }]
                        currentIndex: model.findIndex(m => m.value === (SystemSettings.values.pointer || {}).accelProfile)
                        onActivated: SystemSettings.updateInput("pointer", { accelProfile: currentValue })
                    }
                }
                SettingsRow { label: "Для левой руки"; SettingsToggle { hint: "Поменять кнопки мыши местами"; selected: !!(SystemSettings.values.pointer || {}).leftHanded; onRequested: selected => SystemSettings.updateInput("pointer", { leftHanded: selected }) } }
                SettingsRow { label: "Естественная прокрутка"; SettingsToggle { hint: "Естественная прокрутка мыши"; selected: !!(SystemSettings.values.pointer || {}).naturalScroll; onRequested: selected => SystemSettings.updateInput("pointer", { naturalScroll: selected }) } }
            }
            Group {
                heading: "Тачпад"
                enabled: window.editable && SystemSettings.devices.some(d => d.kind.touchpad)
                SettingsRow { label: "Касание для щелчка"; SettingsToggle { hint: "Касание для щелчка"; selected: !!(SystemSettings.values.touchpad || {}).tapToClick; onRequested: selected => SystemSettings.updateInput("touchpad", { tapToClick: selected }) } }
                SettingsRow { label: "Естественная прокрутка"; SettingsToggle { hint: "Естественная прокрутка тачпада"; selected: !!(SystemSettings.values.touchpad || {}).naturalScroll; onRequested: selected => SystemSettings.updateInput("touchpad", { naturalScroll: selected }) } }
                SettingsRow { label: "Отключать при наборе текста"; SettingsToggle { hint: "Отключать тачпад при наборе текста"; selected: !!(SystemSettings.values.touchpad || {}).disableWhileTyping; onRequested: selected => SystemSettings.updateInput("touchpad", { disableWhileTyping: selected }) } }
                SettingsRow {
                    label: "Скорость прокрутки"
                    Range { value: (SystemSettings.values.touchpad || {}).scrollFactor || 0.3; from: 0.1; to: 3; step: 0.1; hint: "Скорость прокрутки тачпада"; onCommitted: value => SystemSettings.updateInput("touchpad", { scrollFactor: value }) }
                }
            }
            UiText { text: "Тачпад не обнаружен"; visible: !SystemSettings.devices.some(d => d.kind.touchpad); color: Theme.muted; font.pixelSize: 12 }
        }
    }
    Component { id: audioPage; ControlCentre { stats: ({}); sectionMode: "audio"; active: window.visible && SystemSettings.opened } }
    Component { id: connectionsPage; ConnectionsSettings { active: window.visible && SystemSettings.opened } }
    Component {
        id: lockPage
        ColumnLayout {
            spacing: 16
            Group {
                heading: "Обои и предпросмотр локскрина"
                WallpaperSettings { Layout.fillWidth: true; lockScreen: true }
            }
            Group {
                heading: "Бездействие"
                enabled: SystemSettings.loaded && !SystemSettings.busy
                SettingsRow {
                    label: "Блокировать через"
                    description: "Без движения мыши и нажатий клавиш · наш отдельный замок"
                    SettingsChoice {
                        hint: "Таймер блокировки"
                        model: [{ label: "Никогда", value: 0 }].concat([1, 5, 10, 15, 20, 30, 60, 120].map(n => ({ label: n + " мин", value: n })))
                        currentIndex: model.findIndex(m => m.value === SystemSettings.lockMinutes)
                        onActivated: SystemSettings.setIdle(currentValue, SystemSettings.dimMinutes)
                    }
                }
                SettingsRow {
                    label: "Гасить мониторы ещё через"
                    description: "Нужен ShojiWM с управлением питанием мониторов (DPMS) — в текущей сборке его нет"
                    enabled: false
                    SettingsChoice { hint: "Таймер DPMS после блокировки"; model: [{ label: "Недоступно", value: 0 }]; currentIndex: 0 }
                }
                IdleSleepSettings { Layout.fillWidth: true }
            }
            Group {
                heading: "Разблокировка"
                SettingsRow { label: "Вызов экрана блокировки"; UiText { text: "Super + L"; color: Theme.accent; font.pixelSize: 12 } }
                UiText { text: "Пароль — пароль пользователя системы. Замок работает отдельным процессом: перезапуск панели его не снимает."; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 11; color: Theme.muted }
            }
        }
    }
    Component {
        id: appearancePage
        ColumnLayout {
            id: appearance
            property bool extras: false
            spacing: 12
            RowLayout {
                spacing: 8
                SettingsActionButton { text: "Обои"; highlighted: !appearance.extras; onClicked: appearance.extras = false }
                SettingsActionButton { text: "Оформление и эффекты"; highlighted: appearance.extras; onClicked: appearance.extras = true }
            }
            Group {
                heading: "Обои рабочего стола"
                bounded: true
                Layout.fillHeight: true
                visible: !appearance.extras
                DesktopWallpaperSettings {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
                    compact: window.height < 900
                }
            }
            ScrollView {
                id: extrasScroll
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: appearance.extras
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    width: extrasScroll.availableWidth
                    spacing: 16
                    Group {
                        heading: "Наше оформление"
                        UiText { text: "Mocha / Mauve"; font.pixelSize: 22; font.weight: Font.DemiBold; color: Theme.accent }
                        UiText { text: "Noto Sans · матовые поверхности · мелкое статичное зерно"; font.pixelSize: 12; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                        RowLayout {
                            spacing: 8
                            Repeater { model: [Theme.surface, Theme.raised, Theme.hover, Theme.accent, Theme.ink]; Rectangle { required property color modelData; width: 36; height: 26; radius: 7; color: modelData; border.width: 1; border.color: Theme.line } }
                        }
                    }
                    Group {
                        heading: "Курсор и ночной режим"
                        CursorFxSettings { Layout.fillWidth: true }
                        NightLightSettings { Layout.fillWidth: true }
                    }
                    Group {
                        heading: "Обои, эффекты и виджеты"
                        Repeater {
                            model: Quickshell.screens
                            SettingsRow {
                                id: appearanceRow
                                required property var modelData
                                label: modelData.name
                                description: modelData.width + " × " + modelData.height
                                SettingsActionButton { text: "Обои, группы и виджеты"; onClicked: { const name = appearanceRow.modelData.name; SystemSettings.close(); Wallpapers.toggle(name); } }
                                SettingsActionButton { text: "Эффекты"; onClicked: { const name = appearanceRow.modelData.name; SystemSettings.close(); ScreenShaders.toggle(name); } }
                            }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: notificationsPage
        ColumnLayout {
            spacing: 16
            Group {
                heading: "Режим уведомлений"
                SettingsRow {
                    label: "Получать уведомления"
                    description: "При выключении — без новых сообщений, звуков и записей в истории. Исключения выбираются ниже."
                    SettingsToggle { hint: "Получать уведомления"; selected: !Notifications.quiet; enabled: Notifications.loaded; onRequested: selected => Notifications.setQuiet(!selected) }
                }
                UiText { visible: Notifications.error !== ""; text: Notifications.error; color: Theme.danger; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 11 }
                UiText { visible: !Notifications.compositorReady; text: "Политика ShojiWM не подтверждена. Блокировка отдельных окон уведомлений недоступна."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 11 }
                UiText { text: "Собственные сообщения и звуки внутри приложений могут требовать отдельной настройки."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 11 }
                SettingsRow { label: "В истории"; UiText { text: Notifications.count + " / " + Notifications.historyLimit; color: Theme.muted; font.pixelSize: 12 } }
                SettingsActionButton { text: "Очистить историю"; enabled: Notifications.count > 0; onClicked: Notifications.clearAll() }
            }
            Group {
                heading: "Исключения"
                UiText { text: "Эти приложения могут уведомлять даже при выключенном общем переключателе. Критические сообщения сами по себе не являются исключением."; color: Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 11 }
                SettingsField { id: appSearch; Layout.fillWidth: true; placeholderText: "Найти приложение"; Accessible.name: "Поиск исключений уведомлений" }
                ListView {
                    id: exceptionList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(360, contentHeight)
                    clip: true
                    spacing: 6
                    model: Notifications.applications.filter(entry => {
                        const needle = appSearch.text.trim().toLowerCase();
                        return !needle || (entry.name + " " + entry.id).toLowerCase().includes(needle);
                    })
                    ScrollBar.vertical: ScrollBar {}
                    delegate: RowLayout {
                        id: exceptionRow
                        required property var modelData
                        width: exceptionList.width
                        height: 58
                        spacing: 12
                        Image { source: Quickshell.iconPath(exceptionRow.modelData.icon || "application-x-executable", true); sourceSize.width: 24; sourceSize.height: 24; Layout.preferredWidth: 24; Layout.preferredHeight: 24; fillMode: Image.PreserveAspectFit }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            UiText { text: exceptionRow.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 13 }
                            UiText { text: exceptionRow.modelData.id; Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.muted; font.pixelSize: 10 }
                        }
                        SettingsToggle { hint: "Разрешить уведомления: " + exceptionRow.modelData.name; selected: Notifications.isException(exceptionRow.modelData.id); enabled: Notifications.loaded; onRequested: selected => Notifications.setException(exceptionRow.modelData.id, selected) }
                    }
                }
                UiText { visible: exceptionList.count === 0; text: "Приложения не найдены"; color: Theme.muted; font.pixelSize: 12 }
            }
        }
    }
    Component {
        id: displaysPage
        ColumnLayout {
            id: displayPage
            spacing: 16
            // Our monitors.ts owns output configuration (disable, mirror, auto-wake); upstream's output editor is not used.
            Group {
                heading: "Расположение и режимы"
                MonitorSettings { Layout.fillWidth: true; active: window.visible && SystemSettings.opened }
            }
            Group {
                heading: "Яркость монитора"
                Brightness { id: backlight; connector: brightnessOutput.currentValue || "" }
                SettingsRow {
                    label: "Монитор"
                    SettingsChoice {
                        id: brightnessOutput
                        hint: "Монитор для яркости"
                        model: Quickshell.screens.map(s => ({ label: s.name, value: s.name }))
                        currentIndex: 0
                    }
                }
                SettingsActionButton {
                    text: backlight.busy ? "Чтение яркости…" : "Прочитать яркость"
                    enabled: backlight.connector !== "" && !backlight.busy
                    onClicked: backlight.query("get", 0)
                }
                UiText {
                    text: "DDC/CI опрашивается только по кнопке, чтобы открытие раздела и выбор экрана не обращались к мониторам."
                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: 11
                }
                SettingsRow {
                    label: backlight.connector || "Монитор"
                    Range { from: 0; to: 100; step: 1; suffix: "%"; value: backlight.value; enabled: backlight.available && !backlight.busy; hint: "Яркость монитора"; onCommitted: value => backlight.query("set", Math.round(value)) }
                }
                UiText { text: backlight.busy ? "Чтение яркости…" : backlight.error; visible: text !== ""; color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
    }
}
