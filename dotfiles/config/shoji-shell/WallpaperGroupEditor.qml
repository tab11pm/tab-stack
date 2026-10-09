pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    anchors.centerIn: parent
    width: Math.min(760, parent.width - 40)
    height: Math.min(620, parent.height - 40)
    padding: 20
    modal: true
    focus: true
    closePolicy: WallpaperGroups.saving ? Popup.NoAutoClose : Popup.CloseOnEscape
    property string groupId: ""
    property var members: []
    property bool confirmDelete: false
    readonly property int missingCount: members.filter(url => !Wallpapers.imageItems.some(image => image.fileUrl === url)).length

    function edit(id) {
        const group = WallpaperGroups.document.groups.find(item => item.id === id);
        groupId = group ? group.id : "";
        members = group ? group.images.slice() : [];
        nameField.text = group ? group.name : "";
        confirmDelete = false;
        WallpaperGroups.error = "";
        open();
    }
    function toggleImage(url) {
        members = members.includes(url) ? members.filter(item => item !== url) : members.concat([url]);
        confirmDelete = false;
    }
    function save() {
        if (!WallpaperGroups.saving) WallpaperGroups.update(groupId, nameField.text, members);
    }
    function requestPreviews() {
        if (!visible || grid.width <= 0) return;
        const columns = Math.max(1, Math.floor(grid.width / grid.cellWidth));
        const first = Math.max(0, Math.floor(grid.contentY / grid.cellHeight) * columns);
        Wallpapers.requestPreviews(first + columns, columns * 3,
            Wallpapers.imageItems.map(image => image.fileUrl));
    }
    onOpened: {
        grid.contentY = 0;
        nameField.forceActiveFocus();
        Qt.callLater(requestPreviews);
    }
    onClosed: if (parent) parent.forceActiveFocus()
    Connections {
        target: WallpaperGroups
        function onEditSaved() { if (root.visible) root.close(); }
    }
    background: Rectangle { color: Theme.surface; radius: 16; border.color: Theme.line; border.width: 1 }
    Overlay.modal: Rectangle { color: "#99000000" }
    contentItem: ColumnLayout {
        spacing: 12
        Keys.onReturnPressed: event => { root.save(); event.accepted = true; }
        Keys.onEnterPressed: event => { root.save(); event.accepted = true; }
        UiText { text: root.groupId ? "Изменить группу" : "Новая группа"; font.pixelSize: 19; font.weight: Font.DemiBold }
        UiText { text: "Название"; color: Theme.muted; font.pixelSize: 12 }
        TextField {
            id: nameField
            Layout.fillWidth: true
            implicitHeight: 40
            maximumLength: 64
            placeholderText: "Например: Ночь, Утро, Аниме"
            font.family: Theme.font; font.pixelSize: 13
            color: Theme.ink; selectionColor: Theme.accent; selectedTextColor: Theme.surface
            enabled: !WallpaperGroups.saving
            Accessible.name: "Название группы обоев"
            background: Rectangle { radius: 8; color: Theme.raised; border.color: nameField.activeFocus ? Theme.accent : Theme.line }
            onAccepted: root.save()
        }
        RowLayout {
            Layout.fillWidth: true
            UiText { text: "Отметь фотографии · " + root.members.length + " выбрано"; font.pixelSize: 12; Layout.fillWidth: true }
            ActionButton {
                text: "Выбрать все"; implicitHeight: 32; font.pixelSize: 11
                enabled: !WallpaperGroups.saving && Wallpapers.imageItems.length > 0
                onClicked: root.members = Array.from(new Set(root.members.concat(Wallpapers.imageItems.map(image => image.fileUrl))))
            }
            ActionButton {
                text: "Снять выбор"; implicitHeight: 32; font.pixelSize: 11
                enabled: !WallpaperGroups.saving && root.members.length > 0
                onClicked: root.members = []
            }
        }
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            cellWidth: width / Math.max(1, Math.floor(width / 116))
            cellHeight: 106
            clip: true
            model: Wallpapers.imageItems
            boundsBehavior: Flickable.StopAtBounds
            enabled: !WallpaperGroups.saving
            onContentYChanged: root.requestPreviews()
            onWidthChanged: Qt.callLater(root.requestPreviews)
            onCountChanged: Qt.callLater(root.requestPreviews)
            ScrollBar.vertical: ScrollBar {}
            delegate: Button {
                id: tile
                required property int index
                required property var modelData
                width: grid.cellWidth - 8
                height: grid.cellHeight - 8
                checkable: true
                checked: root.members.includes(modelData.fileUrl)
                padding: 5
                Accessible.name: modelData.fileName
                onActiveFocusChanged: if (activeFocus) grid.positionViewAtIndex(index, GridView.Contain)
                onClicked: root.toggleImage(modelData.fileUrl)
                background: Rectangle {
                    radius: 6
                    color: tile.hovered ? Theme.hover : Theme.raised
                    border.width: tile.checked || tile.visualFocus ? 2 : 0
                    border.color: Theme.accent
                }
                contentItem: Item {
                    Image {
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: caption.top; bottomMargin: 5 }
                        source: Wallpapers.thumbnails[tile.modelData.fileUrl] || ""
                        asynchronous: true
                        sourceSize: Qt.size(240, 150)
                        fillMode: Image.PreserveAspectCrop
                    }
                    UiText {
                        id: caption
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        text: tile.modelData.fileName; font.pixelSize: 10
                    }
                    Rectangle {
                        anchors { top: parent.top; right: parent.right; margins: 3 }
                        width: 22; height: 22; radius: 6
                        color: tile.checked ? Theme.accent : Theme.surface
                        border.color: tile.checked ? Theme.accent : Theme.muted
                        UiText { anchors.centerIn: parent; text: tile.checked ? "✓" : ""; color: Theme.surface; font.pixelSize: 14 }
                    }
                }
            }
            UiText {
                anchors.centerIn: parent
                visible: grid.count === 0
                text: "В папке обоев пока нет фотографий"
                color: Theme.muted
            }
        }
        UiText {
            Layout.fillWidth: true
            text: root.missingCount ? "Недоступные фотографии: " + root.missingCount + ". Они останутся в группе." : "Одно фото можно добавить в несколько групп."
            font.pixelSize: 11; color: Theme.muted; wrapMode: Text.Wrap
        }
        UiText {
            Layout.fillWidth: true
            text: WallpaperGroups.error
            visible: !!text
            color: Theme.danger; wrapMode: Text.Wrap; font.pixelSize: 12
            Accessible.role: Accessible.AlertMessage
        }
        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                visible: !!root.groupId
                text: root.confirmDelete ? "Подтвердить удаление" : "Удалить группу"
                hint: "Удалить группу, сохранив фотографии"
                enabled: !WallpaperGroups.saving
                onClicked: {
                    if (root.confirmDelete) WallpaperGroups.remove(root.groupId);
                    else root.confirmDelete = true;
                }
            }
            Item { Layout.fillWidth: true }
            ActionButton { text: "Отмена"; enabled: !WallpaperGroups.saving; onClicked: root.close() }
            ActionButton {
                text: WallpaperGroups.saving ? "Сохранение…" : "Сохранить"
                highlighted: true
                enabled: WallpaperGroups.ready && !WallpaperGroups.saving
                onClicked: root.save()
            }
        }
    }
}
