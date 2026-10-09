function selectPlayer(players, capturePid, mateEngine, ambiguous, selectedName) {
    if (mateEngine || ambiguous) return null;
    var candidates = players.filter(function(p) {
        var metadata = p.metadata || {};
        var pid = Number(metadata["kde:pid"] || 0);
        var browser = /chromium|chrome|firefox|brave|vivaldi|edge|opera/i.test((p.dbusName || "") + " " + (p.identity || ""));
        var webTrack = /^https?:\/\//i.test(String(metadata["xesam:url"] || ""));
        return (browser || webTrack) && (p.canControl || p.trackTitle)
            && !(capturePid > 1 && pid > 1 && pid !== capturePid);
    });
    var exact = capturePid > 1 ? candidates.filter(function(p) {
        return Number((p.metadata || {})["kde:pid"] || 0) === capturePid;
    }) : [];
    if (exact.length) candidates = exact;
    var playing = candidates.filter(function(p) { return p.isPlaying; });
    if (playing.length === 1) return playing[0];
    if (playing.length > 1) return null;
    var retained = candidates.filter(function(p) { return p.dbusName === selectedName; });
    return retained.length === 1 ? retained[0] : candidates.length === 1 ? candidates[0] : null;
}
if (typeof module !== "undefined") module.exports = { selectPlayer: selectPlayer };
