pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "WidgetLayoutState.js" as LayoutState
import "WidgetLibraryState.js" as LibraryState

Popup {
    id: root
    anchors.centerIn: parent
    width: parent.width
    height: parent.height
    padding: 20
    palette.window: Theme.surface
    palette.windowText: Theme.ink
    palette.base: Theme.raised
    palette.text: Theme.ink
    palette.button: Theme.raised
    palette.buttonText: Theme.ink
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.surface
    modal: true
    focus: true
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    property var screenInfos: Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: s.width, height: s.height }))
    property var libraryDraft: LibraryState.load(null, WidgetLayouts.configuredLayouts)
    property string selectedLayoutId: "empty"
    property string deletePendingId: ""
    readonly property var selectedLayout: libraryDraft.layouts.find(value => value.id === selectedLayoutId) || libraryDraft.layouts[0]
    readonly property bool protectedLayout: selectedLayoutId === "empty"
    readonly property var draft: LayoutState.fromLayout(selectedLayout)
    property string selectedId: ""
    property string error: ""
    property bool applying: false
    readonly property bool busy: applying || CustomWidgetLayout.saving || Wallpapers.saving || LiveWallpapers.busy
    readonly property var selectedPlacement: draft.layout.widgets[selectedId] || null
    readonly property var outputOptions: {
        const result = [
            { name: "primary", label: "Главный экран" },
            { name: "secondary", label: WidgetLayouts.secondaryOutput ? "Второй экран" : "Второй экран · не подключён" }
        ];
        if (selectedPlacement && !["primary", "secondary", "right"].includes(selectedPlacement.output))
            result.push({ name: selectedPlacement.output, label: selectedPlacement.output + " · не подключён" });
        return result;
    }
    function edit(layoutId) {
        if (busy) return;
        libraryDraft = LibraryState.validate(CustomWidgetLayout.document || LibraryState.load(null, WidgetLayouts.configuredLayouts));
        selectedLayoutId = libraryDraft.layouts.some(value => value.id === layoutId) ? layoutId : "empty";
        selectedId = Object.keys(selectedLayout.widgets)[0] || "";
        deletePendingId = "";
        error = CustomWidgetLayout.error;
        nameInput.text = selectedLayout.name;
        open();
    }
    function selectLayout(id) {
        if (busy || !libraryDraft.layouts.some(value => value.id === id)) return;
        selectedLayoutId = id;
        selectedId = Object.keys(selectedLayout.widgets)[0] || "";
        deletePendingId = ""; error = "";
        nameInput.text = selectedLayout.name;
    }
    function createLayout(copySelected) {
        if (busy) return;
        try {
            const result = LibraryState.create(libraryDraft, copySelected ? selectedLayout.name + " · копия" : "Новая раскладка", copySelected ? selectedLayoutId : undefined);
            libraryDraft = result.library;
            selectLayout(result.id);
            nameInput.forceActiveFocus(); nameInput.selectAll();
        } catch (failure) { error = failure.message; }
    }
    function renameSelected(name) {
        if (busy || protectedLayout) return;
        try { libraryDraft = LibraryState.rename(libraryDraft, selectedLayoutId, name); error = ""; }
        catch (failure) { error = failure.message; }
    }
    function requestDeleteSelected() {
        if (busy || protectedLayout) return;
        deletePendingId = selectedLayoutId;
    }
    function confirmDeleteSelected() {
        if (busy || !deletePendingId) return;
        try {
            libraryDraft = LibraryState.remove(libraryDraft, deletePendingId);
            selectLayout("empty");
        } catch (failure) { error = failure.message; }
    }
    function commitWidgets(value) {
        libraryDraft = LibraryState.replaceWidgets(libraryDraft, selectedLayoutId, value.layout.widgets);
    }
    function addWidget(id) {
        if (busy || protectedLayout || !Settings.enabled(id) || draft.layout.widgets[id]) return;
        if (!screenInfos.length) { error = "Подключи монитор для добавления виджета."; return; }
        commitWidgets(LayoutState.add(draft, id, { output: "primary", horizontal: "center", vertical: "center", x: 0, y: 0 }));
        selectedId = id; error = "";
    }
    function removeWidget(id) {
        if (busy || protectedLayout) return;
        commitWidgets(LayoutState.remove(draft, id));
        if (selectedId === id) selectedId = Object.keys(draft.layout.widgets)[0] || "";
        error = "";
    }
    function moveWidget(id, outputName, x, y) {
        if (busy || protectedLayout) return;
        const screen = screenInfos.find(s => s.name === outputName);
        const entry = LayoutState.catalog.find(item => item.id === id);
        const role = LayoutState.roleForOutput(outputName, screenInfos, WidgetLayouts.primaryOutputName);
        if (!screen || !entry || !role) return;
        const size = canvas.sizeFor(id, screen);
        const position = LayoutState.clampPosition(x, y, size.width, size.height, screen);
        commitWidgets(LayoutState.place(draft, id, { output: role, horizontal: "left", vertical: "top", x: position.x, y: position.y }));
        selectedId = id; error = "";
    }
    function setPlacementField(field, value) {
        if (busy || protectedLayout || !selectedPlacement) return;
        const placement = Object.assign({}, selectedPlacement);
        placement[field] = value;
        commitWidgets(LayoutState.place(draft, selectedId, placement));
        error = "";
    }
    function apply() {
        if (busy || !CustomWidgetLayout.ready) return;
        if (!protectedLayout) renameSelected(nameInput.text);
        if (error) return;
        applying = true; error = "";
        CustomWidgetLayout.save(libraryDraft);
    }
    function cancel() { if (!busy) close(); }
    onClosed: { if (parent) parent.forceActiveFocus(); }
    Connections {
        target: CustomWidgetLayout
        function onSaved() {
            if (!root.applying) return;
            if (!Wallpapers.activateLayout(root.selectedLayoutId, true)) {
                root.applying = false;
                root.error = "Сейчас раскладка занята переходом. Дождись завершения и повтори.";
            }
        }
        function onSaveFailed() {
            if (!root.applying) return;
            root.applying = false; root.error = CustomWidgetLayout.error;
        }
    }
    Connections {
        target: Wallpapers
        function onLayoutActivated() {
            if (!root.applying) return;
            root.applying = false; root.close();
        }
        function onLayoutActivationFailed() {
            if (!root.applying) return;
            root.applying = false; root.error = Wallpapers.error;
        }
    }
    background: Rectangle { color: Theme.surface; radius: 16; border.color: Theme.line; border.width: 1 }
    Overlay.modal: Rectangle { color: "#99000000" }
    contentItem: ColumnLayout {
        spacing: root.height < 650 ? 8 : 12
        RowLayout {
            Layout.fillWidth: true
            UiText { text: "Раскладки и виджеты"; font.pixelSize: 19; font.weight: Font.DemiBold; Layout.fillWidth: true }
            UiText { text: Object.keys(root.draft.layout.widgets).length + " добавлено"; color: Theme.muted; font.pixelSize: 12 }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ComboBox {
                Layout.fillWidth: true; implicitHeight: root.height < 650 ? 28 : 34
                model: root.libraryDraft.layouts; textRole: "name"
                currentIndex: root.libraryDraft.layouts.findIndex(value => value.id === root.selectedLayoutId)
                enabled: !root.busy; Accessible.name: "Раскладка для редактирования"
                onActivated: index => root.selectLayout(root.libraryDraft.layouts[index].id)
            }
            TextField {
                id: nameInput; Layout.fillWidth: true; implicitHeight: root.height < 650 ? 28 : 34
                text: root.selectedLayout.name; placeholderText: "Название раскладки"
                enabled: !root.busy && !root.protectedLayout
                Accessible.name: "Название раскладки"
                onEditingFinished: root.renameSelected(text)
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            ActionButton { text: "Добавить"; enabled: !root.busy; implicitHeight: 32; font.pixelSize: 11; onClicked: root.createLayout(false) }
            ActionButton { text: "Копировать"; enabled: !root.busy; implicitHeight: 32; font.pixelSize: 11; onClicked: root.createLayout(true) }
            ActionButton { text: "Переименовать"; enabled: !root.busy && !root.protectedLayout; implicitHeight: 32; font.pixelSize: 11; onClicked: root.renameSelected(nameInput.text) }
            ActionButton { text: "Удалить"; enabled: !root.busy && !root.protectedLayout; implicitHeight: 32; font.pixelSize: 11; onClicked: root.requestDeleteSelected() }
            Item { Layout.fillWidth: true }
        }
        RowLayout {
            visible: root.deletePendingId !== ""; Layout.fillWidth: true; enabled: !root.busy
            UiText { Layout.fillWidth: true; text: "Удалить «" + (root.libraryDraft.layouts.find(value => value.id === root.deletePendingId) || {}).name + "»?"; color: Theme.danger; elide: Text.ElideRight }
            ActionButton { text: "Удалить раскладку"; implicitHeight: 30; font.pixelSize: 11; onClicked: root.confirmDeleteSelected() }
            ActionButton { text: "Отмена"; implicitHeight: 30; font.pixelSize: 11; onClicked: root.deletePendingId = "" }
        }
        UiText { Layout.fillWidth: true; text: "Добавь виджет и перетащи его на схеме мониторов. Изменения сохраняются по кнопке «Применить»."; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: 12 }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 16
            ListView {
                id: catalogList
                Layout.preferredWidth: Math.min(240, root.width * 0.28)
                Layout.fillHeight: true
                clip: true; spacing: 6
                model: LayoutState.catalog
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool added: !!root.draft.layout.widgets[modelData.id]
                    readonly property bool available: Settings.enabled(modelData.id)
                    width: catalogList.width; height: 74; radius: 8
                    color: root.selectedId === modelData.id ? Theme.hover : Theme.raised
                    border.width: root.selectedId === modelData.id ? 1 : 0
                    border.color: Theme.accent
                    ColumnLayout {
                        anchors { fill: parent; margins: 8 }
                        spacing: 2
                        UiText { text: row.modelData.label; font.pixelSize: 12; Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 4
                            ActionButton {
                                text: row.added ? "Выбрать" : "Добавить"
                                hint: text + ": " + row.modelData.label
                                implicitHeight: 28; padding: 5; font.pixelSize: 11; Layout.fillWidth: true
                                enabled: !root.busy && !root.protectedLayout && (row.added || row.available)
                                onClicked: { if (row.added) root.selectedId = row.modelData.id; else root.addWidget(row.modelData.id); }
                            }
                            ActionButton {
                                text: "Убрать"; hint: "Убрать: " + row.modelData.label
                                visible: row.added; enabled: !root.busy
                                implicitHeight: 28; padding: 5; font.pixelSize: 11
                                onClicked: root.removeWidget(row.modelData.id)
                            }
                        }
                        UiText { visible: !row.available; text: "Интеграция отключена"; font.pixelSize: 9; color: Theme.muted }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                WidgetLayoutCanvas {
                    id: canvas
                    objectName: "layoutCanvas"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: root.height < 650 ? 120 : 170
                    draft: root.draft; screens: root.screenInfos; selectedId: root.selectedId
                    primary: WidgetLayouts.primaryOutputName
                    enabled: !root.busy
                    onSelected: widgetId => root.selectedId = widgetId
                    onMoved: (widgetId, outputName, localX, localY) => root.moveWidget(widgetId, outputName, localX, localY)
                }
                UiText {
                    text: root.selectedId ? (LayoutState.catalog.find(item => item.id === root.selectedId) || {}).label : "Выбери или добавь виджет"
                    font.pixelSize: 14; font.weight: Font.DemiBold
                }
                GridLayout {
                    visible: !!root.selectedPlacement; enabled: !root.busy
                    Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: root.height < 650 ? 4 : 8
                    UiText { text: "Монитор"; font.pixelSize: 12; color: Theme.muted }
                    ComboBox {
                        Layout.fillWidth: true; implicitHeight: root.height < 650 ? 28 : 34; model: root.outputOptions; textRole: "label"
                        currentIndex: root.selectedPlacement ? root.outputOptions.findIndex(item => item.name === root.selectedPlacement.output) : -1
                        Accessible.name: "Монитор для виджета"
                        onActivated: index => root.setPlacementField("output", root.outputOptions[index].name)
                    }
                    UiText { text: "По горизонтали"; font.pixelSize: 12; color: Theme.muted }
                    ComboBox {
                        Layout.fillWidth: true; implicitHeight: root.height < 650 ? 28 : 34; model: ["Слева", "По центру", "Справа"]
                        currentIndex: root.selectedPlacement ? ["left", "center", "right"].indexOf(root.selectedPlacement.horizontal) : -1
                        Accessible.name: "Горизонтальная привязка"
                        onActivated: index => root.setPlacementField("horizontal", ["left", "center", "right"][index])
                    }
                    UiText { text: "По вертикали"; font.pixelSize: 12; color: Theme.muted }
                    ComboBox {
                        Layout.fillWidth: true; implicitHeight: root.height < 650 ? 28 : 34; model: ["Сверху", "По центру", "Снизу"]
                        currentIndex: root.selectedPlacement ? ["top", "center", "bottom"].indexOf(root.selectedPlacement.vertical) : -1
                        Accessible.name: "Вертикальная привязка"
                        onActivated: index => root.setPlacementField("vertical", ["top", "center", "bottom"][index])
                    }
                    UiText { text: "Смещение X"; font.pixelSize: 12; color: Theme.muted }
                    SpinBox { Layout.fillWidth: true; implicitHeight: root.height < 650 ? 28 : 34; from: -100000; to: 100000; editable: true; value: root.selectedPlacement ? root.selectedPlacement.x : 0; Accessible.name: "Смещение по горизонтали"; onValueModified: root.setPlacementField("x", value) }
                    UiText { text: "Смещение Y"; font.pixelSize: 12; color: Theme.muted }
                    SpinBox { Layout.fillWidth: true; implicitHeight: root.height < 650 ? 28 : 34; from: -100000; to: 100000; editable: true; value: root.selectedPlacement ? root.selectedPlacement.y : 0; Accessible.name: "Смещение по вертикали"; onValueModified: root.setPlacementField("y", value) }
                }
                UiText { Layout.fillWidth: true; text: root.protectedLayout ? "Создай или выбери раскладку для добавления виджетов." : "Home Zone — цельный блок. Каждый тип можно добавить один раз."; color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap }
            }
        }
        UiText { Layout.fillWidth: true; visible: root.error.length > 0; text: root.error; color: Theme.danger; font.pixelSize: 12; wrapMode: Text.Wrap; Accessible.role: Accessible.AlertMessage }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ActionButton { text: "Отмена"; enabled: !root.busy; onClicked: root.cancel() }
            ActionButton { text: root.busy ? "Сохранение…" : "Применить"; highlighted: true; enabled: !root.busy && CustomWidgetLayout.ready && !CustomWidgetLayout.invalidFile; onClicked: root.apply() }
        }
    }
}
