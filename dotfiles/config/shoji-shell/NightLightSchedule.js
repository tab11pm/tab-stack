// Pure local-time scheduling, shared by QML and the self-check.
function validTime(value) {
    return typeof value === "string" && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value);
}
function minutes(value) {
    return Number(value.slice(0, 2)) * 60 + Number(value.slice(3));
}
function normalize(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid settings");
    var start = value.start === undefined ? "22:00" : value.start;
    var end = value.end === undefined ? "07:00" : value.end;
    if (!validTime(start) || !validTime(end)) throw new Error("Invalid time");
    if (start === end) throw new Error("Start and end must be different");
    var temperature = value.temperature === undefined ? 4000 : value.temperature;
    if (typeof temperature !== "number" || !isFinite(temperature) || temperature < 2500 || temperature > 6500)
        throw new Error("Invalid temperature");
    var override = value.override;
    if (override && (typeof override.enabled !== "boolean" || typeof override.until !== "number" || !isFinite(override.until)))
        throw new Error("Invalid override");
    return { scheduled: value.scheduled === true, start: start, end: end,
        temperature: Math.round(temperature), manual: value.manual === true, override: override || null };
}
function effective(config, now) {
    if (!config.scheduled) return config.manual;
    if (config.override && config.override.until > now.getTime()) return config.override.enabled;
    var current = now.getHours() * 60 + now.getMinutes();
    var start = minutes(config.start), end = minutes(config.end);
    return start < end ? current >= start && current < end : current >= start || current < end;
}
function nextBoundary(config, now) {
    var next = Infinity;
    [config.start, config.end].forEach(function(time) {
        var date = new Date(now.getTime());
        date.setHours(Number(time.slice(0, 2)), Number(time.slice(3)), 0, 0);
        if (date.getTime() <= now.getTime()) date.setDate(date.getDate() + 1);
        next = Math.min(next, date.getTime());
    });
    return next;
}
