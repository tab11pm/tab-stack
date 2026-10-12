.import "WidgetLayoutState.js" as Widgets

function validId(id) {
    return typeof id === "string" && /^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(id)
        && ["__proto__", "prototype", "constructor"].indexOf(id) < 0;
}
function cleanName(name) {
    if (typeof name !== "string" || !name.trim()) throw new Error("Введи название раскладки.");
    return name.trim();
}
function cleanLayout(value) {
    if (!Widgets.object(value) || !validId(value.id) || !Widgets.object(value.widgets)
            || ["preset", "custom"].indexOf(value.mode) < 0) throw new Error("Некорректная раскладка.");
    var widgets = {};
    Object.keys(value.widgets).forEach(function (id) {
        if (!Widgets.known(id)) throw new Error("Неизвестный виджет: " + id);
        var entry = Widgets.cleanPlacement(value.widgets[id]);
        if (value.mode === "preset" && value.widgets[id].above !== undefined) {
            if (!Widgets.known(value.widgets[id].above)) throw new Error("Некорректная привязка виджета.");
            entry.above = value.widgets[id].above;
        }
        widgets[id] = entry;
    });
    var name = cleanName(value.name);
    if (value.id === "empty" && (name !== "Без виджетов" || Object.keys(widgets).length || value.mode !== "preset"))
        throw new Error("Раскладка «Без виджетов» защищена.");
    return { id: value.id, name: name, mode: value.mode, widgets: widgets };
}
function validate(value) {
    if (!Widgets.object(value) || value.version !== 2 || !Array.isArray(value.layouts))
        throw new Error("Некорректный файл раскладок или неизвестная версия.");
    var ids = [];
    var layouts = value.layouts.map(function (entry) {
        var next = cleanLayout(entry);
        if (ids.indexOf(next.id) >= 0) throw new Error("Повторяющийся идентификатор раскладки.");
        ids.push(next.id);
        return next;
    });
    if (ids.indexOf("empty") < 0) throw new Error("Отсутствует раскладка «Без виджетов».");
    return { version: 2, layouts: layouts };
}
function load(value, presets) {
    if (value && value.version === 2) return validate(value);
    if (value !== null && value !== undefined && (!Widgets.object(value) || value.version !== 1))
        throw new Error("Неизвестная версия раскладок.");
    var layouts = presets.map(function (entry) {
        return Object.assign({}, entry, {mode: "preset"});
    });
    if (value) {
        var old = Widgets.validate(value).layout;
        layouts.push(Object.assign({}, old, {mode: "custom"}));
    }
    return validate({version: 2, layouts: layouts});
}
function selected(library, id) {
    var entry = library.layouts.find(function (value) { return value.id === id; });
    if (!entry) throw new Error("Раскладка недоступна.");
    return entry;
}
function editable(library, id) {
    var entry = selected(library, id);
    if (id === "empty") throw new Error("Раскладка «Без виджетов» защищена.");
    return entry;
}
function create(library, name, sourceId) {
    var next = validate(library);
    name = cleanName(name);
    var serial = Date.now();
    var id;
    do { id = "user-" + serial++; } while (next.layouts.some(function (value) { return value.id === id; }));
    var widgets = sourceId ? Widgets.fromLayout(selected(next, sourceId)).layout.widgets : {};
    next.layouts.push({id: id, name: name, mode: "custom", widgets: widgets});
    return {library: next, id: id};
}
function rename(library, id, name) {
    var next = validate(library);
    editable(next, id).name = cleanName(name);
    return next;
}
function remove(library, id) {
    var next = validate(library);
    editable(next, id);
    next.layouts = next.layouts.filter(function (value) { return value.id !== id; });
    return next;
}
function replaceWidgets(library, id, widgets) {
    var next = validate(library);
    var entry = editable(next, id);
    entry.widgets = Widgets.fromLayout({widgets: widgets}).layout.widgets;
    entry.mode = "custom";
    return next;
}
