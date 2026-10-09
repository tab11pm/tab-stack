.pragma library

function empty() { return { version: 1, selected: "", groups: [] }; }

function cleanName(value) {
    return typeof value === "string" ? value.replace(/[\x00-\x1f\x7f]/g, " ").trim() : "";
}

function validImage(value) {
    return typeof value === "string" && value.startsWith("file:///") && !/[\x00-\x1f\x7f]/.test(value);
}

function validate(value) {
    if (!value || value.version !== 1 || !Array.isArray(value.groups) || typeof value.selected !== "string")
        throw new Error("Некорректный файл групп обоев");
    const ids = new Set(), names = new Set();
    for (const group of value.groups) {
        const name = cleanName(group && group.name);
        if (!group || typeof group.id !== "string" || !/^group_[a-z0-9_]+$/.test(group.id)
                || ids.has(group.id) || !name || name.length > 64 || name !== group.name
                || names.has(name.toLocaleLowerCase()) || !Array.isArray(group.images)
                || !group.images.every(validImage) || new Set(group.images).size !== group.images.length)
            throw new Error("Некорректная группа обоев");
        ids.add(group.id);
        names.add(name.toLocaleLowerCase());
    }
    if (value.selected && !ids.has(value.selected)) throw new Error("Выбранная группа не существует");
    return value;
}

function saveGroup(document, id, name, images) {
    name = cleanName(name);
    if (!name || name.length > 64) throw new Error("Введи название от 1 до 64 символов");
    if (document.groups.some(group => group.id !== id && group.name.toLocaleLowerCase() === name.toLocaleLowerCase()))
        throw new Error("Группа с таким названием уже есть");
    if (id && !document.groups.some(group => group.id === id)) throw new Error("Группа больше не существует");
    if (!Array.isArray(images) || !images.every(validImage)) throw new Error("Не удалось прочитать список фотографий");
    const identifier = id || "group_" + Date.now().toString(36) + "_" + Math.random().toString(36).slice(2, 10);
    const group = { id: identifier, name: name, images: Array.from(new Set(images)) };
    const groups = id ? document.groups.map(item => item.id === id ? group : item) : document.groups.concat([group]);
    return validate({ version: 1, selected: identifier, groups: groups });
}

function removeGroup(document, id) {
    return validate({ version: 1, selected: document.selected === id ? "" : document.selected,
        groups: document.groups.filter(group => group.id !== id) });
}

function selectGroup(document, id) {
    return validate({ version: 1, selected: id, groups: document.groups });
}

function filterImages(images, document) {
    const group = document.groups.find(item => item.id === document.selected);
    if (!group) return images;
    const members = new Set(group.images);
    return images.filter(image => members.has(image.fileUrl));
}
