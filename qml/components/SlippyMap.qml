import QtQuick 2.2
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0
import "../js/radar.js" as R
import "../js/tilecache.js" as TC

// Custom slippy map: XYZ tiles, radar/lightning overlays placed in
// Web Mercator coordinates, drag / pinch / double tap navigation.
Item {
    id: map
    clip: true

    property real centerLon: 15.5
    property real centerLat: 49.8
    property real zoom: 7
    property real minZoom: 5
    property real maxZoom: 12

    property string mapType: "voyager"
    property real saturation: 1.0

    property var bbox: null
    property string radarSource: ""
    property string lightSource: ""
    property real radarOpacity: 1.0
    property bool smoothRadar: true

    property bool posValid: false
    property real posLat: 0
    property real posLon: 0

    signal interacted()
    signal tapped()

    // ---- projection helpers ----
    readonly property real cnx: R.lonToNx(centerLon)
    readonly property real cny: R.latToNy(centerLat)
    readonly property int tz: Math.max(2, Math.min(18, Math.floor(zoom)))
    readonly property real nTiles: Math.pow(2, tz)
    readonly property real tileScreen: 256 * Math.pow(2, zoom - tz)
    readonly property real cxT: cnx * nTiles
    readonly property real cyT: cny * nTiles
    readonly property int cols: Math.ceil(width / tileScreen) + 3
    readonly property int rows: Math.ceil(height / tileScreen) + 3
    readonly property int startTx: Math.floor(cxT - (width / 2) / tileScreen) - 1
    readonly property int startTy: Math.floor(cyT - (height / 2) / tileScreen) - 1

    function toScreenX(lon) {
        return width / 2 + (R.lonToNx(lon) - cnx) * 256 * Math.pow(2, zoom);
    }

    function toScreenY(lat) {
        return height / 2 + (R.latToNy(lat) - cny) * 256 * Math.pow(2, zoom);
    }

    // Keeps the view centre inside the radar rectangle (bbox). If the viewport
    // is wider/taller than the rectangle, the centre is locked to its middle,
    // so the rectangle stays centred. Zooming is not affected.
    function clampCenter() {
        if (!bbox || width <= 0 || height <= 0) return;
        var s = 256 * Math.pow(2, zoom);
        var hx = (width / 2) / s;
        var hy = (height / 2) / s;
        var bx0 = R.lonToNx(bbox.xmin), bx1 = R.lonToNx(bbox.xmax);
        var by0 = R.latToNy(bbox.ymax), by1 = R.latToNy(bbox.ymin);
        var nx = cnx, ny = cny;
        if (bx1 - bx0 >= 2 * hx) nx = Math.max(bx0 + hx, Math.min(bx1 - hx, nx));
        else nx = (bx0 + bx1) / 2;
        if (by1 - by0 >= 2 * hy) ny = Math.max(by0 + hy, Math.min(by1 - hy, ny));
        else ny = (by0 + by1) / 2;
        if (nx !== cnx) centerLon = R.nxToLon(nx);
        if (ny !== cny) centerLat = R.nyToLat(ny);
    }

    function panBy(dx, dy) {
        var s = 256 * Math.pow(2, zoom);
        centerLon = R.nxToLon(cnx - dx / s);
        centerLat = R.nyToLat(cny - dy / s);
        clampCenter();
    }

    function centerOn(lat, lon) {
        centerLat = lat;
        centerLon = lon;
        clampCenter();
        interacted();
    }

    function setZoom(z) {
        zoom = Math.max(minZoom, Math.min(maxZoom, z));
        clampCenter();
    }

    // Once per start: center on the radar bbox and zoom so that its width
    // matches the display width. Longitude is linear in Web Mercator, so
    // zoom = log2(displayWidth / (256 * bboxWidthInNormalizedUnits)).
    property bool fitted: false

    function fitBbox() {
        if (fitted || !bbox || width <= 0) return;
        var dn = (bbox.xmax - bbox.xmin) / 360;
        if (dn <= 0) return;
        var z = Math.log(width / (256 * dn)) / Math.LN2;
        centerLon = (bbox.xmin + bbox.xmax) / 2;
        centerLat = R.nyToLat((R.latToNy(bbox.ymax) + R.latToNy(bbox.ymin)) / 2);
        zoom = Math.max(minZoom, Math.min(maxZoom, z));
        fitted = true;
    }

    onBboxChanged: { fitBbox(); clampCenter(); }
    // a different radar source has another extent: fit the view to it again
    property string bboxKey: ""
    onBboxKeyChanged: fitted = false   // the next bbox change refits the view
    onWidthChanged: { fitBbox(); clampCenter(); }
    onHeightChanged: clampCenter()

    // ---- base map tiles (desaturated via layer effect) ----
    // Tiles are kept as live Image objects in a cache keyed by "type/z/x/y".
    // Tiles outside the viewport are only hidden, not destroyed, so panning
    // back or zooming out again shows them immediately without re-downloading
    // or flashing blank. Only the oldest hidden tiles are evicted when the
    // cache grows beyond maxCachedTiles.
    readonly property int maxCachedTiles: 400
    property var tileCache: ({})
    property int tileCount: 0
    property int useStamp: 0

    Component {
        id: tileComponent
        Image {
            property int tx: 0
            property int ty: 0
            property int tz: 0
            property string key: ""
            property int stamp: 0
            property string remote: ""
            property bool usingLocal: false

            // size and position computed for this tile's own zoom level
            readonly property real tsize: 256 * Math.pow(2, map.zoom - tz)
            x: map.width / 2 + (tx - map.cnx * Math.pow(2, tz)) * tsize
            y: map.height / 2 + (ty - map.cny * Math.pow(2, tz)) * tsize
            width: tsize
            height: tsize
            asynchronous: true
            cache: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            // Loading is queued and done a few tiles per timer tick (see pumpLoads),
            // so that zooming does not do all the disk reads at once.
            Component.onCompleted: map.queueLoad(tileItem, key, remote)
            id: tileItem

            // fall back to the network if the stored data URL cannot be loaded
            onStatusChanged: {
                if (status === Image.Error && usingLocal) {
                    usingLocal = false;
                    source = remote;
                }
            }
        }
    }

    property var loadQueue: []

    function queueLoad(tile, key, remote) {
        loadQueue.push({ tile: tile, key: key, remote: remote });
    }

    // prefer the disk copy; otherwise download once, show it and store it
    function startLoad(job) {
        var t = job.tile;
        var local = TC.get(job.key);
        if (local !== "") {
            t.usingLocal = true;
            t.source = local;
        } else {
            TC.fetch(job.remote, job.key, function (dataUrl) {
                // the tile may have been evicted (destroyed) in the meantime
                if (dataUrl !== "" && map.tileCache[job.key] === t) {
                    t.usingLocal = true;
                    t.source = dataUrl;
                }
            });
        }
    }

    function pumpLoads() {
        var n = 0;
        while (loadQueue.length > 0 && n < 3) {
            var job = loadQueue.shift();
            // skip only tiles that were destroyed (evicted) meanwhile; tiles that
            // are temporarily outside the view must still load, otherwise they
            // stay blank when they come back into view
            if (map.tileCache[job.key] !== job.tile) continue;
            startLoad(job);
            n++;
        }
    }

    Timer {
        interval: 30
        running: true
        repeat: true
        onTriggered: map.pumpLoads()
    }


    function tileKey(type, z, x, y) {
        return type + "/" + z + "/" + x + "/" + y;
    }

    function updateTiles() {
        if (!tiles) return;
        useStamp++;
        var n = nTiles;
        var wanted = {};
        for (var c = 0; c < cols; c++) {
            for (var r = 0; r < rows; r++) {
                var tx = startTx + c;
                var ty = startTy + r;
                if (ty < 0 || ty >= n) continue;
                var wx = ((tx % n) + n) % n;
                var key = tileKey(mapType, tz, wx, ty);
                wanted[key] = true;
                var t = tileCache[key];
                if (!t) {
                    t = tileComponent.createObject(tiles, {
                        tx: tx,
                        ty: ty,
                        tz: tz,
                        key: key,
                        remote: R.tileUrl(mapType, tz, wx, ty)
                    });
                    tileCache[key] = t;
                    tileCount++;
                }
                t.stamp = useStamp;
                t.visible = true;
            }
        }

        // hide cached tiles that are out of view
        for (var k in tileCache) {
            if (!wanted[k]) tileCache[k].visible = false;
        }

        // evict the oldest hidden tiles when the cache is too large
        if (tileCount > maxCachedTiles) {
            var hidden = [];
            for (var k2 in tileCache) {
                if (!tileCache[k2].visible) hidden.push(tileCache[k2]);
            }
            hidden.sort(function (a, b) { return a.stamp - b.stamp; });
            var excess = tileCount - maxCachedTiles;
            for (var i = 0; i < hidden.length && excess > 0; i++, excess--) {
                delete tileCache[hidden[i].key];
                hidden[i].destroy();
                tileCount--;
            }
        }
    }

    onTzChanged: updateTiles()
    onStartTxChanged: updateTiles()
    onStartTyChanged: updateTiles()
    onColsChanged: updateTiles()
    onRowsChanged: updateTiles()
    onMapTypeChanged: updateTiles()
    Component.onCompleted: updateTiles()

    Item {
        id: tiles
        anchors.fill: parent
        layer.enabled: map.saturation < 0.999
        layer.effect: Desaturate {
            desaturation: 1 - map.saturation
        }
    }

    // ---- RainViewer tile overlay (global radar, zoom capped at RV_MAX_ZOOM) ----
    property bool tileMode: false
    property string tileHost: ""
    property string tilePath: ""
    readonly property int tz2: Math.min(Math.max(2, Math.floor(zoom)), R.RV_MAX_ZOOM)
    readonly property real tileSz: 256 * Math.pow(2, zoom - tz2)
    readonly property real cxT2: cnx * Math.pow(2, tz2)
    readonly property real cyT2: cny * Math.pow(2, tz2)
    readonly property int tcols: Math.ceil(width / tileSz) + 3
    readonly property int trows: Math.ceil(height / tileSz) + 3
    readonly property int tstartX: Math.floor(cxT2 - (width / 2) / tileSz) - 1
    readonly property int tstartY: Math.floor(cyT2 - (height / 2) / tileSz) - 1

    // tiles already downloaded are kept in the local DB (TC), so switching back
    // to a frame is local; the previous frame stays visible until new tiles arrive
    property int pendingLoads: 0
    readonly property bool tilesBusy: pendingLoads > 0

    Repeater {
        id: tileRep
        model: (map.tileMode && map.tilePath !== "") ? map.tcols * map.trows : 0
        delegate: Image {
            readonly property int tx: map.tstartX + (index % map.tcols)
            readonly property int ty: map.tstartY + Math.floor(index / map.tcols)
            readonly property real nT: Math.pow(2, map.tz2)
            readonly property bool onMap: ty >= 0 && ty < nT
            readonly property int wx: ((tx % nT) + nT) % nT
            readonly property string rkey: onMap ? ("rv" + map.tilePath + "/" + map.tz2 + "/" + wx + "/" + ty) : ""
            x: map.width / 2 + (tx - map.cxT2) * map.tileSz
            y: map.height / 2 + (ty - map.cyT2) * map.tileSz
            width: map.tileSz
            height: map.tileSz
            visible: onMap
            asynchronous: true
            smooth: map.smoothRadar
            opacity: map.radarOpacity

            function loadTile() {
                if (rkey === "") return;
                var k = rkey;
                var local = TC.get(k);
                if (local !== "") { source = local; return; }
                map.pendingLoads++;
                TC.fetch(map.tileHost + map.tilePath + "/256/" + map.tz2 + "/" + wx + "/" + ty + "/2/1_1.png", k, function (dataUrl) {
                    map.pendingLoads--;
                    if (dataUrl !== "" && rkey === k) source = dataUrl;
                });
            }
            onRkeyChanged: loadTile()
            Component.onCompleted: loadTile()
        }
    }

    // ---- radar and lightning overlays ----
    Image {
        id: radar
        visible: map.bbox !== null && source !== ""
        source: map.radarSource
        opacity: map.radarOpacity
        fillMode: Image.Stretch
        smooth: map.smoothRadar
        asynchronous: true
        x: map.bbox ? map.toScreenX(map.bbox.xmin) : 0
        y: map.bbox ? map.toScreenY(map.bbox.ymax) : 0
        width: map.bbox ? map.toScreenX(map.bbox.xmax) - map.toScreenX(map.bbox.xmin) : 0
        height: map.bbox ? map.toScreenY(map.bbox.ymin) - map.toScreenY(map.bbox.ymax) : 0
    }

    Image {
        id: lightning
        visible: map.bbox !== null && source !== ""
        source: map.lightSource
        opacity: 0.9
        fillMode: Image.Stretch
        smooth: true
        asynchronous: true
        x: radar.x
        y: radar.y
        width: radar.width
        height: radar.height
    }

    // ---- own position ----
    Item {
        visible: map.posValid
        x: map.toScreenX(map.posLon) - 12
        y: map.toScreenY(map.posLat) - 12
        width: 24
        height: 24
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#405f9bff"
        }
        Rectangle {
            anchors.centerIn: parent
            width: 12
            height: 12
            radius: 6
            color: "#3d8bff"
            border.color: "white"
            border.width: 2
        }
    }

    // ---- gestures (on top of everything) ----
    // Inside the radar rectangle: drag = pan, pinch / double tap = zoom.
    // Outside it: the parent SilicaFlickable handles the drag (pulley menu),
    // so pressInside tells the flickable to stay still for inside presses.
    property bool pressInside: false

    function insideRadar(x, y) {
        // RainViewer has no rectangle: the middle of the map pans/zooms, the
        // top and bottom edges stay free for the pulley menus
        if (tileMode) return y > height * 0.15 && y < height * 0.85;
        if (!bbox) return false;
        return x >= toScreenX(bbox.xmin) && x <= toScreenX(bbox.xmax)
            && y >= toScreenY(bbox.ymax) && y <= toScreenY(bbox.ymin);
    }

    PinchArea {
        id: pinch
        anchors.fill: parent
        property real startZoom: 7
        property bool pinchInside: false
        onPinchStarted: {
            pinchInside = map.insideRadar(pinch.center.x, pinch.center.y);
            startZoom = map.zoom;
        }
        onPinchUpdated: if (pinchInside) map.setZoom(startZoom + Math.log(pinch.scale) / Math.LN2)
        onPinchFinished: if (pinchInside) map.interacted()

        MouseArea {
            anchors.fill: parent
            property real lastX: 0
            property real lastY: 0
            property real pressX: 0
            property real pressY: 0
            property bool inside: false
            onPressed: {
                lastX = mouse.x; lastY = mouse.y;
                pressX = mouse.x; pressY = mouse.y;
                inside = map.insideRadar(mouse.x, mouse.y);
                map.pressInside = inside;
            }
            onPositionChanged: {
                if (inside) map.panBy(mouse.x - lastX, mouse.y - lastY);
                lastX = mouse.x;
                lastY = mouse.y;
            }
            onReleased: {
                map.pressInside = false;
                if (inside) map.interacted();
                // a short press without movement counts as a tap
                if (Math.abs(mouse.x - pressX) < 10 && Math.abs(mouse.y - pressY) < 10)
                    map.tapped();
            }
            onDoubleClicked: {
                if (map.insideRadar(mouse.x, mouse.y)) { map.setZoom(map.zoom + 1); map.interacted(); }
            }
        }
    }
}
