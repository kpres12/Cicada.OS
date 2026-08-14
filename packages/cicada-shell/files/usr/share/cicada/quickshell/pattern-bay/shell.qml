// MAGI-04 // PATTERN BAY — Cicada wallpaper selector.
//
// Visual language: docs/DESIGN.md. A bordered panel with a label tab, an
// instrument ruler, and a legend row — a readout you operate, not a gallery
// you browse. Square corners, hairline rules, no blur, no shadow.
//
// Magnification maths (the scaleFactor binding and the reasons it is one
// binding rather than a chain of animated ones) is adapted from 43PR/dotfiles
// hyprquickpaper, which worked that out correctly; the reasoning is preserved
// in the comments because it is not obvious and is easy to regress.

import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Wayland

PanelWindow {
    id: bay

    // ---- Feel ----
    property int scrollSpeed: 5000
    property int animDuration: 100
    property real zoomScale: 0.86     // plate scale at the centre of the bay
    property real edgeScale: 0.34     // plate scale at the edges
    property int baseSpacing: 10

    // ---- Geometry ----
    readonly property int headerHeight: 30
    readonly property int footerHeight: 64
    readonly property int plateHeight: 420

    implicitHeight: headerHeight + plateHeight + footerHeight + 4
    implicitWidth: Screen.width
    color: "transparent"

    aboveWindows: true
    exclusionMode: "Ignore"
    exclusiveZone: 1

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Component.onCompleted: {
        // Thumbnails are generated on open, not on install: the wallpaper
        // directory is the user's and changes underneath us.
        Quickshell.execDetached(["bash", Quickshell.shellPath("cache.sh"), Quickshell.shellDir])
    }

    FileView {
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: cfg
            property string wallpaper_path
            property string cache_path
            property int plates_across: 9
            property string color_void: "#000000"
            property string color_grid: "#1a1f24"
            property string color_path: "#c45c26"
            property string color_amber: "#ffb000"
            property string color_magi: "#6cffc8"
            property string color_phosphor: "#39ff14"
        }
    }

    FolderListModel {
        id: plates
        folder: "file://" + cfg.wallpaper_path
        showDirs: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.PNG", "*.JPG", "*.JPEG"]
        sortField: FolderListModel.Name
    }

    // Mission time. Zulu, per the console grammar — the bar carries local time.
    property string zulu: "--:--Z"
    function stampZulu() {
        bay.zulu = new Date().toISOString().substr(11, 5) + "Z"
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: bay.stampZulu()
    }

    // ---- Panel ------------------------------------------------------------
    Rectangle {
        id: panel
        anchors.fill: parent
        color: cfg.color_void
        // Opaque enough to read as instrumentation over the desk. Deliberately
        // not a blur pass: blur on a full-width overlay costs frames on the
        // MBA-class prototype, and DESIGN.md forbids blurring the desktop.
        opacity: 0.94
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: cfg.color_path
    }

    // ---- Header -----------------------------------------------------------
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: bay.headerHeight

        // Label tab. The "HELIO MAP" / "DATA FEED" construction: an outlined
        // block sitting on the panel's leading rule.
        Rectangle {
            id: tab
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            width: tabText.implicitWidth + 20
            height: 20
            color: "transparent"
            border.width: 1
            border.color: cfg.color_path

            Text {
                id: tabText
                anchors.centerIn: parent
                text: "MAGI-04 // PATTERN BAY"
                color: cfg.color_amber
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.letterSpacing: 1.6
            }
        }

        Text {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: "PLATES " + plates.count + "   ZULU " + bay.zulu
            color: cfg.color_path
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            font.letterSpacing: 1.4
        }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1
            color: cfg.color_grid
        }
    }

    // ---- Plate row --------------------------------------------------------
    ListView {
        id: row
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
        }
        height: bay.plateHeight
        focus: true

        model: plates
        orientation: ListView.Horizontal
        spacing: bay.baseSpacing
        clip: true
        cacheBuffer: 400

        property int selectedIndex: 0
        property real tileWidth: width / Math.max(1, cfg.plates_across) - 10
        property real viewportCenterX: width / 2

        function clampIndex(i) { return Math.max(0, Math.min(i, count - 1)) }

        // The bay is open on a directory the user can change from another
        // window. If plates disappear underneath the selection, the readout
        // would be asking the model for a row that no longer exists.
        onCountChanged: selectedIndex = clampIndex(selectedIndex)
        function clampX(x) { return Math.max(0, Math.min(x, contentWidth - width)) }

        function activateCurrent() {
            if (count === 0)
                return
            const path = plates.get(selectedIndex, "filePath")
            Quickshell.execDetached(["cicada-wallpaper", "set", path])
            Qt.quit()
        }

        function ensureVisibleAnimated(i) {
            const step = tileWidth + spacing
            const itemStart = i * step
            const itemEnd = itemStart + tileWidth + 20

            if (itemStart < contentX)
                contentX = clampX(itemStart)
            else if (itemEnd > contentX + width)
                contentX = clampX(itemStart - (width - step))
        }

        function moveSelection(delta, speedMultiplier) {
            scrollAnim.v = bay.scrollSpeed * speedMultiplier
            selectedIndex = clampIndex(selectedIndex + delta)
            ensureVisibleAnimated(selectedIndex)
        }

        Behavior on contentX {
            SmoothedAnimation {
                id: scrollAnim
                property int v: bay.scrollSpeed
                duration: bay.animDuration
            }
        }

        delegate: Item {
            id: plate
            height: bay.plateHeight
            property bool active: index === row.selectedIndex

            // Base (unscaled) slot width. Used to work out where this plate
            // currently sits on screen for the magnification curve. Deliberately
            // NOT derived from this item's own dynamic width — if it were, width
            // would depend on position which depends on width: a binding loop.
            readonly property real baseWidth: row.tileWidth

            // Position-driven magnification, as one binding. contentX already
            // animates smoothly, so this recomputes every frame during a scroll;
            // layering a second animation on top makes two animations fight over
            // the same value, which is what reads as sluggish.
            property real scaleFactor: {
                const centerX = x - row.contentX + baseWidth / 2
                const frac = Math.min(1, Math.abs(centerX - row.viewportCenterX) / row.viewportCenterX)
                const t = 1 - frac * frac * (3 - 2 * frac) // smoothstep falloff
                return bay.edgeScale + (bay.zoomScale - bay.edgeScale) * t
            }

            // This is the real layout width, so as a plate grows the ListView
            // pushes the following plates along — actual spacing, not an
            // overlapping overlay.
            width: baseWidth * scaleFactor

            Item {
                id: frame
                anchors.centerIn: parent
                width: parent.width
                height: plate.height * Math.min(1, plate.scaleFactor)

                Text {
                    id: alt
                    text: ""
                    color: cfg.color_path
                    anchors.centerIn: parent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.letterSpacing: 1.4
                }

                Image {
                    id: img
                    anchors.fill: parent
                    // Status by brightness: the selected plate is the live one,
                    // the rest are held. Motion and value carry state here, so
                    // no decorative fade is needed.
                    opacity: plate.active ? 1.0 : 0.45
                    fillMode: Image.PreserveAspectCrop

                    asynchronous: true
                    cache: false
                    smooth: true

                    source: "file://" + cfg.cache_path + fileName

                    // Decode once at the largest size this plate will ever be
                    // shown at, rather than tracking the animating width — that
                    // re-decodes every frame and shows as a blink.
                    sourceSize.width: plate.baseWidth * bay.zoomScale
                    sourceSize.height: plate.height

                    Timer {
                        id: retryTimer
                        interval: 1000
                        repeat: false
                        onTriggered: {
                            const s = img.source
                            img.source = ""
                            img.source = s
                        }
                    }

                    onStatusChanged: {
                        if (status === Image.Error) {
                            alt.text = "CACHING"
                            retryTimer.start()
                        } else if (status === Image.Ready) {
                            alt.text = ""
                        }
                    }
                }

                // Held plates get a grid hairline; the live plate gets a magi
                // hairline plus phosphor corner brackets — a target reticle,
                // not a picture frame.
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: plate.active ? cfg.color_magi : cfg.color_grid
                }

                Item {
                    id: reticle
                    anchors.fill: parent
                    visible: plate.active

                    readonly property int arm: 18
                    readonly property int weight: 2
                    readonly property color ink: cfg.color_phosphor

                    // Eight rectangles, written out. A Repeater over corner
                    // descriptors is shorter but puts the geometry behind an
                    // index lookup, and this is the one shape in the bay that
                    // has to be pixel-exact in all four corners.
                    Rectangle { x: 0; y: 0; width: reticle.arm; height: reticle.weight; color: reticle.ink }
                    Rectangle { x: 0; y: 0; width: reticle.weight; height: reticle.arm; color: reticle.ink }

                    Rectangle { x: parent.width - width; y: 0; width: reticle.arm; height: reticle.weight; color: reticle.ink }
                    Rectangle { x: parent.width - width; y: 0; width: reticle.weight; height: reticle.arm; color: reticle.ink }

                    Rectangle { x: 0; y: parent.height - height; width: reticle.arm; height: reticle.weight; color: reticle.ink }
                    Rectangle { x: 0; y: parent.height - height; width: reticle.weight; height: reticle.arm; color: reticle.ink }

                    Rectangle { x: parent.width - width; y: parent.height - height; width: reticle.arm; height: reticle.weight; color: reticle.ink }
                    Rectangle { x: parent.width - width; y: parent.height - height; width: reticle.weight; height: reticle.arm; color: reticle.ink }
                }
            }

            // Mouse is a first-class path here, not an afterthought:
            // cicada-desktop.mdc requires everything reachable without a keybind.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                onEntered: row.selectedIndex = index
                onClicked: row.activateCurrent()

                onWheel: function(wheel) {
                    row.flick(-wheel.angleDelta.y * 8, 0)
                    wheel.accepted = true
                }
            }
        }

        Keys.onPressed: function(event) {
            const page = Math.max(1, cfg.plates_across)

            switch (event.key) {
            case Qt.Key_J:
            case Qt.Key_Right:
                moveSelection(1, 1)
                break
            case Qt.Key_K:
            case Qt.Key_Left:
                moveSelection(-1, 1)
                break
            case Qt.Key_D:
            case Qt.Key_PageDown:
                moveSelection(page, page)
                break
            case Qt.Key_U:
            case Qt.Key_PageUp:
                moveSelection(-page, page)
                break
            case Qt.Key_Home:
                moveSelection(-count, page)
                break
            case Qt.Key_End:
                moveSelection(count, page)
                break
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                activateCurrent()
                break
            case Qt.Key_Escape:
                Qt.quit()
                break
            default:
                return
            }

            event.accepted = true
        }
    }

    // ---- Footer -----------------------------------------------------------
    Item {
        id: footer
        anchors { top: row.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 1
            color: cfg.color_grid
        }

        // Instrument ruler. Ticks are a scale, not decoration: the tall tick
        // marks the selected plate's position through the whole set.
        Row {
            id: ruler
            anchors { top: parent.top; topMargin: 5; left: parent.left; right: parent.right }
            height: 8
            spacing: 0

            Repeater {
                model: 120

                Item {
                    id: tick
                    required property int index
                    width: ruler.width / 120
                    height: 8

                    readonly property bool major: tick.index % 10 === 0
                    readonly property bool cursor: plates.count > 0
                        && Math.round(row.selectedIndex / Math.max(1, plates.count - 1) * 119) === tick.index

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: 1
                        height: tick.cursor ? 8 : (tick.major ? 5 : 2)
                        color: tick.cursor ? cfg.color_phosphor : cfg.color_grid
                    }
                }
            }
        }

        // Readout row: index, plate name, then the key legend.
        Item {
            anchors {
                top: ruler.bottom
                topMargin: 6
                left: parent.left
                right: parent.right
                leftMargin: 14
                rightMargin: 14
            }
            height: 16

            Text {
                id: indexReadout
                anchors.left: parent.left
                text: plates.count > 0
                    ? "PLATE " + String(row.selectedIndex + 1).padStart(3, "0")
                      + "/" + String(plates.count).padStart(3, "0")
                    : "PLATE ---/---"
                color: cfg.color_amber
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.letterSpacing: 1.2
            }

            Text {
                anchors { left: indexReadout.right; leftMargin: 18; right: legend.left; rightMargin: 18 }
                text: plates.count > 0 ? plates.get(row.selectedIndex, "fileName") : "NO PLATES IN BAY"
                color: cfg.color_magi
                elide: Text.ElideMiddle
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Text {
                id: legend
                anchors.right: parent.right
                text: "◆ LIVE   ◇ HELD   J/K ◂ ▸ SCROLL   ENTER SET   ESC ABORT"
                color: cfg.color_path
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.letterSpacing: 1.2
            }
        }

        // Empty-bay guidance. A console that shows nothing and explains nothing
        // reads as broken; say where the plates are meant to live.
        Text {
            anchors.centerIn: parent
            visible: plates.count === 0
            text: "DROP IMAGES IN " + cfg.wallpaper_path.toUpperCase()
            color: cfg.color_path
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            font.letterSpacing: 1.4
        }
    }

    // Click-away dismiss. Escape works, but the pointer should never be trapped.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: Qt.quit()
    }
}
