pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "WallpaperGroupState.js" as GroupState

Singleton {
    id: root
    property var document: GroupState.empty()
    property var pendingDocument: null
    property bool ready: false
    property bool saving: false
    property string error: ""
    readonly property string selected: document.selected
    readonly property var images: GroupState.filterImages(Wallpapers.imageItems, document)
    readonly property var options: [{ id: "", name: "Все изображения", count: Wallpapers.imageItems.length }].concat(
        document.groups.map(group => ({ id: group.id, name: group.name,
            count: Wallpapers.imageItems.filter(image => group.images.includes(image.fileUrl)).length })))
    signal editSaved()
    property bool editing: false

    function select(id) {
        if (!ready || saving || selected === id) return;
        try { save(GroupState.selectGroup(document, id), false); }
        catch (failure) { error = failure.message; }
    }
    function update(id, name, members) {
        if (!ready || saving) return;
        try { save(GroupState.saveGroup(document, id, name, members), true); }
        catch (failure) { error = failure.message; }
    }
    function remove(id) {
        if (!ready || saving) return;
        try { save(GroupState.removeGroup(document, id), true); }
        catch (failure) { error = failure.message; }
    }
    function save(value, isEdit) {
        pendingDocument = value;
        editing = isEdit;
        saving = true;
        error = "";
        try {
            const serialized = JSON.stringify(value, null, 4) + "\n";
            if (state.text() === serialized) complete();
            else state.setText(serialized);
        } catch (failure) { fail(); }
    }
    function complete() {
        if (!saving || !pendingDocument) return;
        document = pendingDocument;
        pendingDocument = null;
        saving = false;
        error = "";
        const wasEditing = editing;
        editing = false;
        if (wasEditing) editSaved();
    }
    function fail() {
        pendingDocument = null;
        saving = false;
        editing = false;
        error = "Не удалось сохранить группы. Повтори попытку.";
    }
    FileView {
        id: state
        path: Settings.configHome + "/shoji-shell/wallpaper-groups.json"
        preload: true
        printErrors: false
        atomicWrites: true
        onLoaded: {
            if (root.ready) return;
            try {
                root.document = GroupState.validate(JSON.parse(text()));
                root.ready = true;
            } catch (failure) { root.error = "Не удалось прочитать wallpaper-groups.json. Проверь файл групп."; }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) root.ready = true;
            else root.error = "Не удалось прочитать группы обоев";
        }
        onSaved: root.complete()
        onSaveFailed: root.fail()
    }
}
