// Pure launcher logic, also exercised by the external Node fixture tests.
// Ordered subsequence DP: reward adjacency and word/camel-case boundaries;
// penalize skipped characters. This is deliberately not claimed as fzf parity.
function fuzzyScore(needle, value) {
    var original = String(value || "");
    var text = original.toLowerCase();
    if (!needle || needle.length > text.length) return -Infinity;
    var previous = [];
    for (var i = 0; i < needle.length; i++) {
        var row = [];
        var bestGap = -Infinity;
        for (var j = 0; j < text.length; j++) {
            if (i > 0 && j > 0) bestGap = Math.max(bestGap - 1, previous[j - 1] - 1);
            var boundary = j === 0 || /[\s._/\-]/.test(text[j - 1])
                || (original[j] !== text[j] && original[j - 1] === text[j - 1]);
            var prior = i === 0 ? -j : Math.max(bestGap, j > 0 ? previous[j - 1] + 12 : -Infinity);
            row[j] = text[j] === needle[i] ? prior + 16 + (boundary ? 12 : 0) : -Infinity;
        }
        previous = row;
    }
    var best = -Infinity;
    for (var k = 0; k < previous.length; k++) best = Math.max(best, previous[k]);
    if (best === -Infinity) return best;
    var quality = Math.max(0, Math.min(900, 400 + best / needle.length * 10 - text.length / 10));
    if (text === needle) return 4000;
    if (text.startsWith(needle)) return 3000 + quality;
    var at = text.indexOf(needle);
    if (at >= 0) return 1000 + quality + (/[\s._/\-]/.test(text[at - 1]) ? 500 : 0);
    return quality;
}

function filterApps(apps, query) {
    var needle = query.trim().toLowerCase();
    if (!needle) return [];
    var scored = [];
    for (var i = 0; i < apps.length; i++) {
        var app = apps[i];
        var score = Math.max(fuzzyScore(needle, app.name), fuzzyScore(needle, app.genericName) * 0.65,
                             fuzzyScore(needle, app.comment) * 0.3);
        var keywords = app.keywords || [];
        for (var k = 0; k < keywords.length; k++) score = Math.max(score, fuzzyScore(needle, keywords[k]) * 0.5);
        if (score !== -Infinity) scored.push({ app: app, score: score });
    }
    scored.sort(function(a, b) {
        if (a.score !== b.score) return b.score - a.score;
        var an = a.app.name.toLowerCase(), bn = b.app.name.toLowerCase();
        if (an !== bn) return an < bn ? -1 : 1;
        return a.app.id < b.app.id ? -1 : a.app.id === b.app.id ? 0 : 1;
    });
    return scored.map(function(item) { return item.app; });
}

function nextMode(mode, forward) {
    // a87ce49 advertises window mode, but the target Rofi Wayland build's
    // working window mode has not been verified. Do not invent a switcher.
    var modes = ["drun", "run"];
    return modes[(Math.max(0, modes.indexOf(mode)) + (forward ? 1 : modes.length - 1)) % modes.length];
}

function tabAction(backtab, control, shift) {
    var reverse = backtab || shift;
    return control ? (reverse ? "modePrevious" : "modeNext") : (reverse ? "previous" : "next");
}

function geometry(width, height, preferredWidth, padding, count, errorHeight) {
    var margin = 12;
    var available = Math.max(0, height - 2 * margin);
    var fixed = 32 + 2 * padding + (errorHeight ? errorHeight + 4 : 0);
    var list = count ? Math.max(0, Math.min(Math.min(12, count) * 30 - 2, available - fixed - 4)) : 0;
    return { width: Math.max(0, Math.min(preferredWidth, width - 2 * margin)),
             height: Math.min(available, fixed + (list ? list + 4 : 0)), listHeight: list };
}
