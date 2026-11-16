// tilecache.js - persistent on-disk cache for map tiles (QtQuick.LocalStorage).
// Tiles are stored as base64 data URLs keyed by "type/z/x/y".
// .pragma library: shared module state, no QML objects.
.pragma library
.import QtQuick.LocalStorage 2.0 as LS

// Bump the name whenever the tile sources change, so old tiles (e.g. wrong
// provider stored under the "voyager" key) are not reused.
var DB_NAME = "meteoradar_tiles_v4";
var MAX_TILES = 1500;   // roughly 40-60 MB depending on tile size
var db = null;

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function handle() {
    if (!db) {
        db = LS.LocalStorage.openDatabaseSync(DB_NAME, "1.0", "Map tile cache", 100000000);
        db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS tiles (key TEXT PRIMARY KEY, data TEXT, ts INTEGER)");
        });
    }
    return db;
}

// Returns the stored data URL for key, or "" when not cached.
// Read-only on purpose: a write per read made zooming slow.
function get(key) {
    var res = "";
    try {
        handle().readTransaction(function (tx) {
            var rs = tx.executeSql("SELECT data FROM tiles WHERE key = ?", [key]);
            if (rs.rows.length > 0) res = rs.rows.item(0).data;
        });
    } catch (e) {
        res = "";
    }
    return res;
}

var putCount = 0;

function put(key, dataUrl) {
    try {
        handle().transaction(function (tx) {
            tx.executeSql("INSERT OR REPLACE INTO tiles (key, data, ts) VALUES (?, ?, ?)",
                          [key, dataUrl, Date.now()]);
            // trim to MAX_TILES every 20 writes (not on every write)
            putCount++;
            if (putCount % 20 === 0) {
                tx.executeSql("DELETE FROM tiles WHERE key IN " +
                              "(SELECT key FROM tiles ORDER BY ts DESC LIMIT -1 OFFSET ?)",
                              [MAX_TILES]);
            }
        });
    } catch (e) {
        // cache is best effort; ignore storage errors
    }
}

function toBase64(bytes) {
    var out = [];
    var n = bytes.length;
    var i = 0;
    var v = 0;
    for (; i + 2 < n; i += 3) {
        v = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
        out.push(B64[(v >> 18) & 63] + B64[(v >> 12) & 63] + B64[(v >> 6) & 63] + B64[v & 63]);
    }
    var rem = n - i;
    if (rem === 1) {
        v = bytes[i] << 16;
        out.push(B64[(v >> 18) & 63] + B64[(v >> 12) & 63] + "==");
    } else if (rem === 2) {
        v = (bytes[i] << 16) | (bytes[i + 1] << 8);
        out.push(B64[(v >> 18) & 63] + B64[(v >> 12) & 63] + B64[(v >> 6) & 63] + "=");
    }
    return out.join("");
}

// Returns the MIME type for a known image signature, or "" if unknown.
function imageMime(bytes) {
    if (bytes.length > 4 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47)
        return "image/png";
    if (bytes.length > 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF)
        return "image/jpeg";
    return "";
}

// Downloads an image (no caching) and calls cb(dataUrl), or cb("") on failure.
function loadImage(url, cb) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        var dataUrl = "";
        if (xhr.status === 200 && xhr.response) {
            try {
                var bytes = new Uint8Array(xhr.response);
                var mime = imageMime(bytes);
                if (mime !== "") dataUrl = "data:" + mime + ";base64," + toBase64(bytes);
            } catch (e) {
                dataUrl = "";
            }
        }
        try { cb(dataUrl); } catch (e) { }
    };
    xhr.open("GET", url);
    try { xhr.setRequestHeader("User-Agent", "harbour-meteoradar/1.0.0"); } catch (e) { }
    xhr.responseType = "arraybuffer";
    xhr.send();
}

// Downloads a tile, stores it under key and calls cb(dataUrl).
// cb receives "" unless the response is HTTP 200 with a real PNG/JPEG body
// (error pages such as OSM "Access blocked" must never be cached).
function fetch(url, key, cb) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        var dataUrl = "";
        if (xhr.status === 200 && xhr.response) {
            try {
                var bytes = new Uint8Array(xhr.response);
                var mime = imageMime(bytes);
                if (mime !== "") {
                    dataUrl = "data:" + mime + ";base64," + toBase64(bytes);
                    put(key, dataUrl);
                }
            } catch (e) {
                dataUrl = "";
            }
        }
        try { cb(dataUrl); } catch (e) { /* tile was already destroyed */ }
    };
    xhr.open("GET", url);
    try { xhr.setRequestHeader("User-Agent", "harbour-meteoradar/1.0.0"); } catch (e) { }
    xhr.responseType = "arraybuffer";
    xhr.send();
}
