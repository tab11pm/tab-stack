// Pure layout data. No credentials, live collectors or Qt objects belong here.
var catalog = [
    { id: "limits", label: "Лимиты AI", width: 286, height: 270 },
    { id: "sessions", label: "Сессии", width: 340, height: 270 },
    { id: "neko", label: "Котик", width: 210, height: 210 },
    { id: "github", label: "GitHub", width: 286, height: 330 },
    { id: "profile", label: "Профиль", width: 340, height: 300 },
    { id: "hermes", label: "Hermes", width: 480, height: 64 },
    { id: "deepseek", label: "DeepSeek API", width: 286, height: 190 },
    { id: "music", label: "Музыка", width: 286, height: 280 },
    { id: "weather", label: "Погода", width: 286, height: 160 },
    { id: "activity", label: "Время за ПК", width: 420, height: 630 },
    { id: "home", label: "Home Zone", width: 852, height: 690 },
    { id: "gaming-home", label: "Home Zone · Gaming", width: 1468, height: 420 }
];

function known(id) { return catalog.some(function (item) { return item.id === id; }); }
function object(value) { return !!value && typeof value === "object" && !Array.isArray(value); }
function cleanPlacement(value) {
    if (!object(value) || typeof value.output !== "string" || !value.output.trim()
            || ["left", "center", "right"].indexOf(value.horizontal) < 0
            || ["top", "center", "bottom"].indexOf(value.vertical) < 0
            || typeof value.x !== "number" || !Number.isFinite(value.x)
            || typeof value.y !== "number" || !Number.isFinite(value.y))
        throw new Error("Некорректное расположение виджета");
    return { output: value.output, horizontal: value.horizontal, vertical: value.vertical, x: value.x, y: value.y };
}
function fromLayout(layout) {
    if (!object(layout) || !object(layout.widgets)) throw new Error("Некорректная раскладка");
    var widgets = {};
    Object.keys(layout.widgets).forEach(function (id) {
        if (!known(id)) throw new Error("Неизвестный виджет: " + id);
        widgets[id] = cleanPlacement(layout.widgets[id]);
    });
    return { version: 1, layout: { id: "custom", name: "Своя раскладка", widgets: widgets } };
}
function validate(value) {
    if (!object(value) || value.version !== 1 || !object(value.layout) || value.layout.id !== "custom")
        throw new Error("Некорректный файл раскладки или неизвестная версия");
    return fromLayout(value.layout);
}
function add(document, id, placement) {
    if (!known(id)) throw new Error("Неизвестный виджет");
    var next = validate(document);
    if (Object.prototype.hasOwnProperty.call(next.layout.widgets, id)) throw new Error("Виджет уже добавлен");
    next.layout.widgets[id] = cleanPlacement(placement);
    return next;
}
function remove(document, id) {
    var next = validate(document);
    delete next.layout.widgets[id];
    return next;
}
function place(document, id, placement) {
    var next = validate(document);
    if (!known(id) || !Object.prototype.hasOwnProperty.call(next.layout.widgets, id)) throw new Error("Виджет не добавлен");
    next.layout.widgets[id] = cleanPlacement(placement);
    return next;
}
function primaryScreenName(screens, primary) {
    var connected = screens.some(function (screen) { return screen.name === primary; });
    return connected ? primary : (screens[0] || {}).name || null;
}
function resolveOutput(reference, screens, primary) {
    var main = primaryScreenName(screens, primary);
    if (reference === "primary") return main;
    if (reference === "secondary" || reference === "right") {
        var other = screens.find(function (screen) { return screen.name !== main; });
        return other ? other.name : null;
    }
    return reference;
}
function roleForOutput(name, screens, primary) {
    var main = primaryScreenName(screens, primary);
    if (name === main) return "primary";
    var other = screens.find(function (screen) { return screen.name !== main; });
    return other && other.name === name ? "secondary" : name;
}
function clampPosition(x, y, width, height, screen) {
    return { x: Math.round(Math.max(0, Math.min(Math.max(0, screen.width - width), x))),
        y: Math.round(Math.max(0, Math.min(Math.max(0, screen.height - height), y))) };
}
function toPosition(placement, width, height, screen) {
    return { x: placement.horizontal === "right" ? screen.width - width - placement.x
            : placement.horizontal === "center" ? (screen.width - width) / 2 + placement.x : placement.x,
        y: placement.vertical === "bottom" ? screen.height - height - placement.y
            : placement.vertical === "center" ? (screen.height - height) / 2 + placement.y : placement.y };
}
