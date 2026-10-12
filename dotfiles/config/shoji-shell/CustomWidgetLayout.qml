pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "WidgetLibraryState.js" as LibraryState

Singleton {
    id: root
    property var document: null
    property var savedDocument: null
    property var pendingDocument: null
    property bool ready: false
    property bool saving: false
    property bool writeFailed: false
    property bool invalidFile: false
    property string error: ""
    property int revision: 0
    signal saved()
    signal saveFailed()

    function save(value) {
        if (!ready || saving) return;
        if (invalidFile) {
            error = "Исправь или переименуй widget-layouts.json перед сохранением раскладки.";
            saveFailed();
            return;
        }
        try {
            pendingDocument = LibraryState.validate(value);
            saving = true;
            error = "";
            const serialized = JSON.stringify(pendingDocument, null, 4) + "\n";
            // FileView retains the failed payload in its cache. A harmless extra
            // newline forces a real retry instead of treating cached text as saved.
            const cached = state.text();
            if (cached === serialized && !writeFailed) complete();
            else state.setText(writeFailed && cached === serialized ? serialized + "\n" : serialized);
        } catch (failure) { fail(); }
    }
    function complete() {
        if (!saving || !pendingDocument) return;
        writeFailed = false;
        savedDocument = pendingDocument;
        pendingDocument = null;
        saving = false;
        error = "";
        saved();
    }
    function fail() {
        writeFailed = true;
        pendingDocument = null;
        saving = false;
        error = "Не удалось сохранить widget-layouts.json. Проверь доступ к файлу и повтори.";
        saveFailed();
    }
    // Publication is deliberately separate from disk writes: Wallpapers must
    // successfully save the selection before the live desktop sees this draft.
    function publish() {
        if (!savedDocument) return;
        document = LibraryState.validate(savedDocument);
        revision++;
    }
    FileView {
        id: state
        path: Settings.configHome + "/shoji-shell/widget-layouts.json"
        preload: true
        printErrors: false
        atomicWrites: true
        onLoaded: {
            if (root.ready) return;
            try {
                root.document = LibraryState.load(JSON.parse(text()), WidgetLayouts.configuredLayouts);
                root.savedDocument = root.document;
            } catch (failure) {
                root.invalidFile = true;
                root.error = "Не удалось прочитать widget-layouts.json. Исправь файл и перезагрузи оболочку.";
            }
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.document = LibraryState.load(null, WidgetLayouts.configuredLayouts);
                root.savedDocument = root.document;
            } else {
                root.invalidFile = true;
                root.error = "Не удалось прочитать widget-layouts.json. Проверь доступ к файлу.";
            }
            root.ready = true;
        }
        onSaved: root.complete()
        onSaveFailed: root.fail()
    }
}
