// radar.js - data access and map math for harbour-meteoradar.
// .pragma library: pure functions and constants, no QML objects.
.pragma library

// Set by the root window (harbour-meteoradar.qml) so pages can reach app state
var app = null;

var INIT_URL = "https://data-provider.chmi.cz/api/map/init/radary.radary?client=mobile";
var DATA_BASE = "https://data-provider.chmi.cz/api/data/pocasi/";

// Note: ArcGIS uses {z}/{y}/{x} order. No API key needed.
// OpenStreetMap is not used: it answers the app with HTTP 418 "Access blocked".
var TILE_TEMPLATES = {
    voyager: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}",
    relief: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
    dark: "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}"
};

function dataUrl(kind, ref) {
    return DATA_BASE + kind + "/" + ref;
}

function tileUrl(type, z, x, y) {
    var t = TILE_TEMPLATES[type] || TILE_TEMPLATES.voyager;
    return t.replace("{z}", z).replace("{x}", x).replace("{y}", y);
}

// Plain XMLHttpRequest GET -> cb(err, parsedJson)
function getJson(url, cb) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status === 200) {
            try { cb(null, JSON.parse(xhr.responseText)); }
            catch (e) { cb("Neplatná odpověď: " + e, null); }
        } else {
            cb("HTTP " + xhr.status, null);
        }
    };
    xhr.open("GET", url);
    xhr.send();
}

// "202611091305" (UTC) -> epoch ms
function parseRef(ref) {
    var y = parseInt(ref.substr(0, 4), 10);
    var mo = parseInt(ref.substr(4, 2), 10) - 1;
    var d = parseInt(ref.substr(6, 2), 10);
    var h = parseInt(ref.substr(8, 2), 10);
    var mi = parseInt(ref.substr(10, 2), 10);
    return Date.UTC(y, mo, d, h, mi);
}

function pad2(n) { return (n < 10 ? "0" : "") + n; }

// local HH:MM for epoch ms
function hm(t) {
    var d = new Date(t);
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

// Parse init JSON: returns { bbox: {xmin,ymin,xmax,ymax} (lon/lat), refs: [{t, ref}] }
// refs are limited to [now - historyMinutes, end of nowcast], sorted by time.
function parseInit(json, historyMinutes, nowMs) {
    var radar = null;
    for (var i = 0; i < json.layers.length; i++) {
        if (json.layers[i].id === "radary") { radar = json.layers[i]; break; }
    }
    if (!radar) throw "Vrstva radaru nenalezena";

    var bb = null;
    for (var b = 0; b < json.boundingBoxes.length; b++) {
        if (json.boundingBoxes[b].id === "main") { bb = json.boundingBoxes[b]; break; }
    }
    if (!bb) throw "Chybí bounding box radaru";

    var from = nowMs - historyMinutes * 60000;
    var refs = [];
    for (var p = 0; p < radar.dataParts.length; p++) {
        var ref = radar.dataParts[p].dataRef;
        var t = parseRef(ref);
        if (t >= from) refs.push({ t: t, ref: ref });
    }
    refs.sort(function (a, c) { return a.t - c.t; });
    return {
        bbox: { xmin: bb.xmin, ymin: bb.ymin, xmax: bb.xmax, ymax: bb.ymax },
        refs: refs
    };
}

// ---- radar sources ----
// chmi: Czech Hydrometeorological Institute (JSON frames, lightning available)
// wms:  WMS composites, one PNG per time step rendered over a lon/lat bbox (EPSG:3857)
var STEP_MS = 300000;
// RainViewer: global composite as XYZ tiles; the frame list gives host + paths
var RV_URL = "https://api.rainviewer.com/public/weather-maps.json";
var RV_MAX_ZOOM = 7;

var SOURCES = {
    chmi: { label: "ČHMÚ", attribution: "ČHMÚ", kind: "chmi" },
    dwd: {
        label: "DWD (Německo)", attribution: "DWD", kind: "wms",
        url: "https://maps.dwd.de/geoserver/dwd/wms",
        layer: "dwd:Niederschlagsradar",
        // lon/lat extent of the composite rendered into the image
        bbox: { xmin: 5.5, ymin: 46.5, xmax: 16.0, ymax: 55.5 }
    },
    rv: {
        label: "RainViewer", attribution: "RainViewer", kind: "tiles"
    },
    fmi: {
        label: "FMI (Finsko)", attribution: "FMI", kind: "wms",
        url: "https://openwms.fmi.fi/geoserver/wms",
        layer: "Radar:radar_finland_cappi_dbzh",
        bbox: { xmin: 15.3, ymin: 57.1, xmax: 42.7, ymax: 70.8 }
    }
};

function mercX(lon) { return lon * Math.PI / 180 * 6378137; }
function mercY(lat) { return Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360)) * 6378137; }

// WMS GetMap URL of one frame of source src (time = epoch ms, 5-minute aligned)
function wmsFrameUrl(src, t) {
    var s = SOURCES[src];
    var b = s.bbox;
    var bb = [mercX(b.xmin), mercY(b.ymin), mercX(b.xmax), mercY(b.ymax)].join(",");
    return s.url + "?service=WMS&version=1.1.1&request=GetMap&layers=" + s.layer
        + "&styles=&srs=EPSG:3857&bbox=" + bb + "&width=512&height=512&format=image/png"
        + "&transparent=true&time=" + new Date(t).toISOString();
}

// 5-minute steps from (now - historyMinutes) up to now
function wmsRefs(nowMs, historyMinutes) {
    var end = Math.floor(nowMs / STEP_MS) * STEP_MS;
    var start = end - historyMinutes * 60000;
    var refs = [];
    for (var t = start; t <= end; t += STEP_MS) refs.push({ t: t, ref: "" + t });
    return refs;
}

function wmsBbox(src) {
    var b = SOURCES[src].bbox;
    return { xmin: b.xmin, ymin: b.ymin, xmax: b.xmax, ymax: b.ymax };
}

// ---- Web Mercator helpers (normalized 0..1, y grows southwards) ----
function lonToNx(lon) { return (lon + 180) / 360; }

function latToNy(lat) {
    var phi = lat * Math.PI / 180;
    return (1 - Math.log(Math.tan(Math.PI / 4 + phi / 2)) / Math.PI) / 2;
}

function nxToLon(nx) { return nx * 360 - 180; }

function nyToLat(ny) {
    return (2 * Math.atan(Math.exp(Math.PI * (1 - 2 * ny))) - Math.PI / 2) * 180 / Math.PI;
}
