import QtQuick 2.2
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import Nemo.DBus 2.0
import "js/radar.js" as R
import "js/tilecache.js" as TC
import "pages"
import "cover"

ApplicationWindow {
    id: win

    allowedOrientations: Orientation.All
    // Publishes the window as R.app so that pages and the cover can reach the
    // shared state (evaluated once; the value itself is not used)
    property var appRef: { R.app = win; return win; }

    initialPage: Component { MainPage { } }
    cover: Component { CoverPage { } }

    ConfigurationGroup {
        id: settings
        path: "/apps/harbour-meteoradar"
        property real centerLon: 15.5
        property real centerLat: 49.8
        property real zoom: 7
        property real radarOpacity: 1.0         // radar is always fully visible
        property string mapType: "voyager"      // voyager | relief | dark
        property string radarSource: "chmi"     // key of R.SOURCES: chmi | dwd | fmi
        property real saturation: 1.0           // 0 = greyscale base map, 1 = colour
        property bool showPosition: false
        property bool smoothRadar: true
        property bool lightning: false
        property int historyMinutes: 60         // 60 | 120 | 360
        property int playInterval: 430          // ms per frame (about 40 % faster than 600)
        property string cache: ""               // JSON {t, img} of last observed frame
    }
    property var cfg: settings

    // ---- radar state ----
    property var frames: []          // [{t, ref, img}] radar frames (img = data URI)
    property var lightFrames: []     // same indexing as frames, lightning layer
    property int current: 0
    property bool playing: false
    property bool autoPlayed: false
    property bool loading: false
    property string rvHost: ""     // RainViewer tile host (from weather-maps.json)
    // RainViewer: path of the current frame (empty for other sources)
    readonly property string currentTilePath: (cfg.radarSource === "rv" && currentFrame) ? currentFrame.ref : ""
    property int loadTotal: 0      // DWD: number of frames being downloaded
    property int loadDone: 0       // DWD: frames finished so far
    property string errorText: ""
    property var bbox: null          // {xmin, ymin, xmax, ymax} in degrees
    property real now: Date.now()

    // ---- position ----
    property bool posValid: false
    property real posLat: 0
    property real posLon: 0

    readonly property var currentFrame: frames.length > current ? frames[current] : null
    readonly property string currentRadar: (currentFrame && currentFrame.img) ? currentFrame.img : ""
    readonly property string currentLight: (lightFrames.length > current && lightFrames[current].img) ? lightFrames[current].img : ""
    readonly property string frameLabel: currentFrame ? R.hm(currentFrame.t) : "--:--"
    readonly property bool frameIsForecast: currentFrame ? currentFrame.t > now : false

    function pickCurrent() {
        var idx = 0;
        for (var i = 0; i < frames.length; i++) {
            if (frames[i].t <= now) idx = i;
        }
        current = idx;
    }

    function stepForward() {
        if (frames.length > 0) current = (current + 1) % frames.length;
    }

    // Loads one image per reference; cb receives the full array when all are done.
    function loadFrames(kind, refs, cb) {
        var out = new Array(refs.length);
        var pending = refs.length;
        if (pending === 0) { cb([]); return; }
        for (var i = 0; i < refs.length; i++) {
            (function (i) {
                R.getJson(R.dataUrl(kind, refs[i].ref), function (err, j) {
                    out[i] = { t: refs[i].t, ref: refs[i].ref,
                               img: (!err && j && j.img) ? j.img : "" };
                    pending--;
                    if (pending === 0) cb(out);
                });
            })(i);
        }
    }

    function saveCache(list) {
        for (var i = list.length - 1; i >= 0; i--) {
            if (list[i].t <= now && list[i].img) {
                cfg.cache = JSON.stringify({ t: list[i].t, img: list[i].img, src: cfg.radarSource });
                return;
            }
        }
    }

    function loadCache() {
        if (!cfg.cache) return;
        try {
            var c = JSON.parse(cfg.cache);
            // only restore a frame that belongs to the currently selected source
            if ((c.src || "chmi") !== cfg.radarSource) return;
            frames = [{ t: c.t, ref: "", img: c.img }];
            current = 0;
        } catch (e) {
            cfg.cache = "";
        }
    }

    // Sets the frames shown on the map and keeps/starts the animation.
    // list must contain only frames with an image.
    function setFrames(list) {
        frames = list;
        if (!playing) pickCurrent();
        // start the animation automatically from the current time, once per app start
        if (!autoPlayed) {
            autoPlayed = true;
            playing = true;
        }
        else if (current >= list.length) current = 0;
    }

    // Shared by all sources: final result of a refresh
    function applyFrames(list) {
        loading = false;
        loadTotal = 0;
        loadDone = 0;
        var ok = list.filter(function (f) { return f.img !== ""; });
        if (ok.length === 0) {
            errorText = qsTr("Žádná data radaru");
            return;
        }
        setFrames(ok);
        saveCache(ok);
    }

    // Each refresh gets a generation number; results of an older refresh (e.g.
    // DWD frames still downloading after switching to CHMU) are ignored.
    property int refreshGen: 0

    function refresh(force) {
        if (loading && !force) return;
        var gen = ++refreshGen;
        var kind = R.SOURCES[cfg.radarSource].kind;
        if (kind === "wms") { refreshWms(gen); return; }
        if (kind === "tiles") { refreshRv(gen); return; }
        loading = true;
        errorText = "";
        now = Date.now();
        R.getJson(R.INIT_URL, function (err, json) {
            if (gen !== refreshGen) return;
            if (err) {
                loading = false;
                errorText = qsTr("Radar se nepodařilo načíst (%1)").arg(err);
                return;
            }
            var p;
            try {
                p = R.parseInit(json, cfg.historyMinutes, Date.now());
            } catch (e) {
                loading = false;
                errorText = "" + e;
                return;
            }
            bbox = p.bbox;
            loadFrames("radary", p.refs, function (list) {
                if (gen === refreshGen) applyFrames(list);
            });
            if (cfg.lightning) {
                loadFrames("blesky", p.refs, function (list) {
                    if (gen === refreshGen) lightFrames = list;
                });
            } else {
                lightFrames = [];
            }
        });
    }

    // RainViewer: frames are tile paths (rvHost + path), drawn as a tile overlay
    function refreshRv(gen) {
        loading = true;
        errorText = "";
        now = Date.now();
        lightFrames = [];
        bbox = null;
        R.getJson(R.RV_URL, function (err, json) {
            if (gen !== refreshGen) return;
            loading = false;
            if (err || !json || !json.radar) {
                errorText = qsTr("RainViewer se nepodařilo načíst (%1)").arg(err || "data");
                return;
            }
            rvHost = json.host;
            var from = now - cfg.historyMinutes * 60000;
            var past = json.radar.past || [];
            var list = [];
            for (var i = 0; i < past.length; i++) {
                if (past[i].time * 1000 >= from)
                    list.push({ t: past[i].time * 1000, ref: past[i].path, img: "" });
            }
            if (list.length === 0) {
                errorText = qsTr("Žádná data radaru");
                return;
            }
            // RainViewer allows ~500 tile requests per minute, one frame needs ~50
            // tiles: show the newest frame only, no automatic animation
            setFrames(list);
            current = list.length - 1;
            playing = false;
        });
    }

    // WMS sources (DWD, FMI): one image per 5-minute step, no lightning layer.
    // Frames are shown as soon as they arrive (time order, gaps skipped).
    function refreshWms(gen) {
        var src = cfg.radarSource;
        loading = true;
        errorText = "";
        now = Date.now();
        lightFrames = [];
        bbox = R.wmsBbox(src);
        var refs = R.wmsRefs(now, cfg.historyMinutes);
        var out = new Array(refs.length);
        var pending = refs.length;
        loadTotal = refs.length;
        loadDone = 0;
        for (var i = 0; i < refs.length; i++) {
            (function (i) {
                TC.loadImage(R.wmsFrameUrl(src, refs[i].t), function (dataUrl) {
                    if (gen !== refreshGen) return;   // superseded by a newer refresh
                    out[i] = { t: refs[i].t, ref: refs[i].ref, img: dataUrl };
                    pending--;
                    loadDone++;
                    if (pending === 0) {
                        applyFrames(out);
                        return;
                    }
                    if (dataUrl !== "") {
                        // show what is already loaded, in time order
                        var partial = out.filter(function (f) { return f && f.img !== ""; });
                        if (partial.length > 0) setFrames(partial);
                    }
                });
            })(i);
        }
    }

    // Selects the radar source (key of R.SOURCES) and reloads the frames
    function setRadarSource(src) {
        if (cfg.radarSource === src) return;
        cfg.radarSource = src;
        frames = [];
        lightFrames = [];
        current = 0;
        playing = false;
        autoPlayed = false;   // play the new source's animation from its start
        loadTotal = 0;
        loadDone = 0;
        refresh(true);        // force: a DWD download may still be running
    }


    // Clock: updates "now" (used for observed/forecast split)
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: win.now = Date.now()
    }

    // Auto refresh as CHMU updates every ~5 min (init refreshInterval 180 s)
    Timer {
        interval: 180000
        running: true
        repeat: true
        onTriggered: win.refresh()
    }

    // Animation
    Timer {
        interval: cfg.playInterval
        running: win.playing && win.frames.length > 1 && win.cfg.radarSource !== "rv"
        repeat: true
        onTriggered: win.stepForward()
    }

    Connections {
        target: Qt.application
        onActiveChanged: {
            if (Qt.application.active) win.refresh();
        }
    }

    // Quit over D-Bus so the compositor is not disturbed (see README)
    DBusAdaptor {
        bus: DBus.SessionBus
        service: "cz.mig.harbour-meteoradar"
        path: "/"
        iface: "cz.mig.harbour_meteoradar"
        xml: '<interface name="cz.mig.harbour_meteoradar">' +
             '<method name="quit"/>' +
             '</interface>'
        function quit() { Qt.quit(); }
    }

    Component.onCompleted: {
        loadCache();
        refresh();
    }
}
