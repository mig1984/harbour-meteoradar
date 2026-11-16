import QtQuick 2.2
import Sailfish.Silica 1.0

// Timeline of radar frames: past (observed) frames in primary colour,
// nowcast frames in highlight colour, current frame emphasised.
Item {
    id: tl

    property var frames: []
    property int current: 0
    property bool playing: false
    signal selected(int index)
    signal playToggled()

    readonly property int count: frames.length
    // the frame restored from the cache has no reference (ref === ""): it is
    // only a placeholder for the map image, so no bars are drawn for it
    readonly property bool placeholder: count === 1 && frames[0].ref === ""
    readonly property int barCount: placeholder ? 0 : count
    readonly property real step: barCount > 0 ? barArea.width / barCount : 0

    function indexAt(x) {
        if (count === 0) return 0;
        return Math.max(0, Math.min(count - 1, Math.floor(x / step)));
    }

    IconButton {
        id: playBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        icon.source: tl.playing ? "image://theme/icon-m-pause" : "image://theme/icon-m-play"
        onClicked: tl.playToggled()
    }

    Item {
        id: barArea
        anchors.left: playBtn.right
        anchors.right: parent.right
        anchors.rightMargin: Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.itemSizeExtraSmall

        Repeater {
            model: tl.barCount
            delegate: Rectangle {
                readonly property bool isCurrent: index === tl.current
                readonly property bool forecast: tl.frames[index] ? tl.frames[index].t > Date.now() : false
                x: index * tl.step + 1
                width: Math.max(2, tl.step - 2)
                height: isCurrent ? barArea.height : barArea.height * 0.6
                anchors.bottom: parent.bottom
                radius: 2
                color: isCurrent ? "#7fd4ff"
                       : (forecast ? Theme.highlightColor : Theme.primaryColor)
                opacity: isCurrent ? 1 : (forecast ? 0.6 : 0.45)
            }
        }

        MouseArea {
            anchors.fill: parent
            onPressed: tl.selected(tl.indexAt(mouse.x))
            onPositionChanged: if (pressed) tl.selected(tl.indexAt(mouse.x))
        }
    }
}
