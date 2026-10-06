// macOS-style dock: one frosted row of pinned and running apps, a divider,
// then Downloads and Trash. Magnifies under the pointer, a dot under running
// apps, a name label on hover, bounce on launch.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "logic.js" as Logic

Item {
    id: root

    property var shell: null

    readonly property int iconSize: 48
    readonly property int maxIconSize: 76
    // How far magnification reaches either side of the pointer, in px.
    readonly property int reach: 170
    readonly property int slotWidth: iconSize + 10
    readonly property int dividerWidth: 17
    readonly property int pad: 5
    readonly property int barHeight: iconSize + 18
    readonly property int margin: 6
    readonly property int labelRoom: 38
    // Transparent room above the bar so a dragged icon stays visible.
    readonly property int dragRoom: 110

    // ── Pins ────────────────────────────────────────────────────────────
    FileView {
        id: pinFile
        path: Quickshell.env("HOME") + "/.config/omarchy/jack-dock.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: pins
            property list<string> pinned: []
            // Grow icons under the pointer. Off by default.
            property bool magnification: false
            onPinnedChanged: Qt.callLater(root.rebuild)
        }
    }

    function togglePin(key) {
        const list = Array.from(pins.pinned);
        const i = list.indexOf(key);
        if (i >= 0) list.splice(i, 1); else list.push(key);
        pins.pinned = list;
    }

    // ── Apps ────────────────────────────────────────────────────────────
    // Desktop entry by id variants → StartupWMClass → app name in title (PWAs).
    function entryFor(cls, title) {
        const clsLower = cls.toLowerCase();
        for (const v of [cls, clsLower, cls.replace(/-/g, ""), cls.split(".")[0]]) {
            const e = v && DesktopEntries.byId(v);
            if (e && e.icon) return e;
        }
        const all = DesktopEntries.applications.values;
        for (const e of all)
            if (e.startupClass && e.startupClass.toLowerCase() === clsLower && e.icon) return e;
        const titleLower = (title || "").toLowerCase();
        if (titleLower)
            for (const e of all) {
                const n = (e.name || "").toLowerCase();
                if (n && titleLower.includes(n) && e.icon) return e;
            }
        return null;
    }

    function iconFor(entry, cls) {
        if (entry) return Quickshell.iconPath(entry.icon, "application-x-executable");
        for (const v of [cls, cls.toLowerCase(), cls.split("-")[0], cls.split(".").pop()]) {
            const p = v && Quickshell.iconPath(v, true);
            if (p) return p;
        }
        return Quickshell.iconPath("application-x-executable");
    }

    property var apps: []
    property string appsSignature: ""

    // Rebuilt only when the set of apps or windows changes, so title churn
    // doesn't recreate the icons (and cut a hover or bounce short).
    function rebuild() {
        const wins = [];
        for (const t of Hyprland.toplevels.values) {
            const cls = (t.wayland && t.wayland.appId) || (t.lastIpcObject && t.lastIpcObject.class) || "";
            if (!cls) continue;
            const entry = root.entryFor(cls, t.title);
            wins.push({ key: entry ? entry.id : cls, cls: cls, entry: entry, top: t });
        }
        const list = Logic.groupApps(Array.from(pins.pinned), wins);
        for (const a of list) {
            const w = a.windows[0];
            a.entry = w ? w.entry : DesktopEntries.byId(a.key);
            // Browser app windows without a desktop file (class
            // brave-<extension id>-Default) carry the app name as title.
            a.name = a.entry ? a.entry.name
                : (w && /^(brave|chrome|chromium)-[a-p]{32}-/.test(w.cls)) ? w.top.title : a.key;
            a.icon = root.iconFor(a.entry, w ? w.cls : a.key);
        }
        const sig = JSON.stringify(list.map(a => [a.key, a.name, a.windows.map(w => w.top.address)]));
        if (sig === root.appsSignature) return;
        root.appsSignature = sig;
        root.apps = list;
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { Qt.callLater(root.rebuild) }
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { Qt.callLater(root.rebuild) }
    }

    // Most recent focus time per window address, to reopen an app's last window.
    property var lastFocus: ({})
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            const t = Hyprland.activeToplevel;
            if (t) root.lastFocus[t.address] = Date.now();
            // A new window's title (which names PWAs) settles after it opens.
            Qt.callLater(root.rebuild);
        }
    }
    Component.onCompleted: rebuild()

    // ── Actions ─────────────────────────────────────────────────────────
    function addr(t) {
        const a = String(t.address);
        return a.startsWith("0x") ? a : "0x" + a;
    }

    function launch(app) {
        Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", app.entry.id + ".desktop"]);
    }

    // Click: launch if closed; bring back the app's last window (restoring it
    // from the minimize scratchpad); when it's already in front, cycle its windows.
    function activate(app, slot) {
        if (!app.windows.length) {
            if (app.entry) { root.launch(app); slot.bounce(); }
            return;
        }
        const wins = app.windows.slice().sort((a, b) =>
            (root.lastFocus[root.addr(b.top)] || 0) - (root.lastFocus[root.addr(a.top)] || 0));
        const active = Hyprland.activeToplevel;
        const i = wins.findIndex(w => active && w.top.address === active.address);
        const target = i >= 0 ? wins[(i + 1) % wins.length].top : wins[0].top;
        if (i >= 0 && wins.length === 1) return;
        const sel = '"address:' + root.addr(target) + '"';
        let cmd = "";
        const ws = target.workspace;
        if (ws && String(ws.name).startsWith("special:") && Hyprland.focusedWorkspace)
            cmd += "hyprctl dispatch 'hl.dsp.window.move({ workspace = \"" + Hyprland.focusedWorkspace.id
                + "\", window = " + sel + ", follow = false })'; ";
        // Focusing warps the pointer to the window; keep it on the dock.
        Quickshell.execDetached(["sh", "-c",
            "prev=false; hyprctl getoption cursor:no_warps | grep -q 'bool: true' && prev=true; "
            + "hyprctl eval 'hl.config({ cursor = { no_warps = true } })'; " + cmd
            + "hyprctl dispatch 'hl.dsp.focus({ window = " + sel + " })'; "
            + "sleep 0.3; hyprctl eval \"hl.config({ cursor = { no_warps = $prev } })\""]);
    }

    function quit(app) {
        for (const w of app.windows) if (w.top.wayland) w.top.wayland.close();
    }

    function openPath(uri) {
        Quickshell.execDetached(["uwsm-app", "--", "nautilus", uri]);
    }

    // ── Slots: apps | divider | Downloads, Trash ────────────────────────
    readonly property var slots: {
        const s = root.apps.map(a => ({ kind: "app", app: a, name: a.name, icon: a.icon }));
        if (s.length) s.push({ kind: "divider" });
        s.push({ kind: "folder", name: "Downloads", icon: Quickshell.iconPath("folder-download", "folder") });
        s.push({ kind: "trash", name: "Trash", icon: Quickshell.iconPath("user-trash", "folder") });
        return s;
    }
    readonly property var widths: slots.map(s => s.kind === "divider" ? root.dividerWidth : root.slotWidth)
    readonly property real restWidth: widths.reduce((a, b) => a + b, 0)

    // ── Drag to reorder ─────────────────────────────────────────────────
    // dragFrom: slot index being dragged (-1 for none); dragTo: the position
    // it would drop at. dragPoint is the pointer in the panel's coordinates.
    property int dragFrom: -1
    property int dragTo: -1
    property point dragPoint: Qt.point(0, 0)
    // Dragged well above the bar: dropping removes the app from the dock.
    readonly property bool dragRemoves: dragFrom >= 0 && dragPoint.y < panel.barY - 60

    function drop() {
        const from = root.dragFrom, to = root.dragTo, removes = root.dragRemoves;
        root.dragFrom = -1;
        const app = root.apps[from];
        if (removes) {
            if (app.pinned) root.togglePin(app.key);
            return;
        }
        if (from !== to)
            pins.pinned = Logic.pinsAfterDrop(root.apps.map(a => a.key), Array.from(pins.pinned), from, to, !!app.entry);
    }

    // ── Menu state ──────────────────────────────────────────────────────
    property var menuSlot: null
    property real menuX: 0
    property real menuY: 0

    PanelWindow {
        id: panel

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "jack-dock"
        anchors { bottom: true; left: true; right: true }
        exclusiveZone: root.barHeight + root.margin
        implicitHeight: root.margin + root.barHeight + (root.maxIconSize - root.iconSize) + root.labelRoom + root.dragRoom
        color: "transparent"

        // Pointer in resting-row coordinates; kept after leaving so the
        // magnification shrinks back where it was.
        readonly property real rowLeft: (width - root.restWidth) / 2
        property var mouseRow: null
        property real amount: hover.hovered && pins.magnification ? 1 : 0
        Behavior on amount { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        readonly property var geo: Logic.layout(root.widths, root.slots.map(s => s.kind !== "divider"),
            mouseRow, amount, root.iconSize, root.maxIconSize, root.reach)
        readonly property real barY: height - root.margin - root.barHeight
        readonly property int hoveredIndex: {
            if (!hover.hovered) return -1;
            const x = hover.point.position.x - rowLeft;
            for (let i = 0; i < geo.x.length; i++)
                if (x >= geo.x[i] && x < geo.x[i] + geo.w[i]) return root.slots[i].kind === "divider" ? -1 : i;
            return -1;
        }

        // Input only over the bar, plus the magnified icons above it while hovered.
        mask: Region { item: hitArea }

        Item {
            id: content
            anchors.fill: parent

            HoverHandler {
                id: hover
                onPointChanged: if (hovered) panel.mouseRow = point.position.x - panel.rowLeft
            }

            Item {
                id: hitArea
                x: bar.x
                width: bar.width
                y: hover.hovered && pins.magnification ? panel.barY - (root.maxIconSize - root.iconSize) : panel.barY
                height: panel.height - y
            }

            // Frosted glass; Hyprland blurs behind it (layer rule on "jack-dock").
            Rectangle {
                id: bar
                x: panel.rowLeft + panel.geo.start - root.pad
                width: panel.geo.end - panel.geo.start + 2 * root.pad
                y: panel.barY
                height: root.barHeight
                radius: 20
                color: Qt.alpha(Color.background, 0.42)
                border.color: Qt.alpha(Color.foreground, 0.16)
                border.width: 1

                // Soft top sheen, like light catching the glass.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.07) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
            }

            Repeater {
                model: root.slots

                Item {
                    id: slot
                    required property var modelData
                    required property int index

                    // Position in the row; differs from index while an app is dragged.
                    readonly property int pos: Logic.dragPos(index, root.dragFrom, root.dragTo)
                    readonly property real mag: panel.geo.s[pos] || 1
                    readonly property real size: root.iconSize * mag
                    readonly property bool dragged: root.dragFrom === index
                    property real lift: 0
                    property point pressAt: Qt.point(0, 0)
                    // Set once a press turns into a drag, so the release isn't also a click.
                    property bool didDrag: false

                    function bounce() { bounceAnim.restart() }

                    x: panel.rowLeft + (panel.geo.x[pos] || 0)
                    width: panel.geo.w[pos] || 0
                    // Neighbours slide aside to open a gap for the dragged icon.
                    Behavior on x {
                        enabled: root.dragFrom >= 0 && !slot.dragged
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    y: panel.barY + root.barHeight - 11 - size
                    height: panel.height - y

                    // Divider: a thin vertical line, like the one before Downloads.
                    Rectangle {
                        visible: slot.modelData.kind === "divider"
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: panel.barY - slot.y + 10
                        width: 1
                        height: root.barHeight - 20
                        color: Qt.alpha(Color.foreground, 0.28)
                    }

                    Image {
                        visible: slot.modelData.kind !== "divider" && !slot.dragged
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -slot.lift
                        width: slot.size
                        height: slot.size
                        source: slot.modelData.icon || ""
                        sourceSize: Qt.size(root.maxIconSize * 2, root.maxIconSize * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    // Running dot.
                    Rectangle {
                        visible: slot.modelData.kind === "app" && slot.modelData.app.windows.length > 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: slot.size + 4
                        width: 4
                        height: 4
                        radius: 2
                        color: Qt.alpha(Color.foreground, 0.85)
                    }

                    SequentialAnimation {
                        id: bounceAnim
                        loops: 2
                        NumberAnimation { target: slot; property: "lift"; to: 22; duration: 230; easing.type: Easing.OutQuad }
                        NumberAnimation { target: slot; property: "lift"; to: 0; duration: 230; easing.type: Easing.InQuad }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: slot.modelData.kind !== "divider"
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPressed: mouse => {
                            slot.pressAt = mapToItem(content, mouse.x, mouse.y);
                            slot.didDrag = false;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed || slot.modelData.kind !== "app" || !(mouse.buttons & Qt.LeftButton)) return;
                            const p = mapToItem(content, mouse.x, mouse.y);
                            if (root.dragFrom < 0) {
                                if (Math.hypot(p.x - slot.pressAt.x, p.y - slot.pressAt.y) < 6) return;
                                slot.didDrag = true;
                                root.dragTo = slot.index;
                                root.dragFrom = slot.index;
                            }
                            root.dragPoint = p;
                            // Drop position: the app slot whose centre is nearest the pointer.
                            const x = p.x - panel.rowLeft;
                            let best = 0;
                            for (let i = 1; i < root.apps.length; i++)
                                if (Math.abs(x - panel.geo.x[i] - panel.geo.w[i] / 2)
                                    < Math.abs(x - panel.geo.x[best] - panel.geo.w[best] / 2)) best = i;
                            root.dragTo = best;
                        }
                        onReleased: if (root.dragFrom === slot.index) root.drop()
                        onClicked: mouse => {
                            if (slot.didDrag) return;
                            const s = slot.modelData;
                            if (mouse.button === Qt.RightButton) {
                                root.menuSlot = s;
                                root.menuX = slot.x + slot.width / 2;
                                root.menuY = slot.y - 8;
                                return;
                            }
                            if (s.kind === "app") root.activate(s.app, slot);
                            else if (s.kind === "folder") root.openPath(Quickshell.env("HOME") + "/Downloads");
                            else root.openPath("trash:///");
                        }
                    }
                }
            }

            // The dragged icon, following the pointer.
            Image {
                visible: root.dragFrom >= 0
                width: root.iconSize
                height: root.iconSize
                x: root.dragPoint.x - width / 2
                y: root.dragPoint.y - height / 2
                source: root.dragFrom >= 0 ? root.slots[root.dragFrom].icon : ""
                sourceSize: Qt.size(root.maxIconSize * 2, root.maxIconSize * 2)
                opacity: root.dragRemoves ? 0.5 : 1
                smooth: true
                mipmap: true

                Rectangle {
                    visible: root.dragRemoves && root.slots[root.dragFrom].app.pinned
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 6
                    width: removeText.implicitWidth + 20
                    height: removeText.implicitHeight + 10
                    radius: 7
                    color: Qt.alpha(Color.background, 0.9)
                    border.color: Qt.alpha(Color.foreground, 0.14)
                    border.width: 1

                    Text {
                        id: removeText
                        anchors.centerIn: parent
                        text: "Remove"
                        color: Color.foreground
                        font.pixelSize: 13
                    }
                }
            }

            // Name label above the hovered icon.
            Rectangle {
                id: label
                readonly property int i: panel.hoveredIndex
                visible: i >= 0 && !root.menuSlot && root.dragFrom < 0
                width: labelText.implicitWidth + 20
                height: labelText.implicitHeight + 10
                radius: 7
                x: i >= 0 ? panel.rowLeft + panel.geo.x[i] + panel.geo.w[i] / 2 - width / 2 : 0
                y: i >= 0 ? panel.barY + root.barHeight - 11 - root.iconSize * panel.geo.s[i] - height - 8 : 0
                color: Qt.alpha(Color.background, 0.9)
                border.color: Qt.alpha(Color.foreground, 0.14)
                border.width: 1

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    text: label.i >= 0 ? root.slots[label.i].name : ""
                    color: Color.foreground
                    font.pixelSize: 13
                }
            }
        }

    }

    // Right-click menu: a transparent fullscreen overlay, so a click anywhere
    // outside the menu closes it. (HyprlandFocusGrab never fired here.)
    PanelWindow {
        id: menu
        visible: !!root.menuSlot
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "jack-dock-menu"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.menuSlot = null
        }

        readonly property var items: {
            const s = root.menuSlot;
            if (!s) return [];
            if (s.kind === "folder") return [{ text: "Open", run: () => root.openPath(Quickshell.env("HOME") + "/Downloads") }];
            if (s.kind === "trash") return [
                { text: "Open", run: () => root.openPath("trash:///") },
                { text: "Empty Trash", run: () => Quickshell.execDetached(["gio", "trash", "--empty"]) }];
            const a = s.app, out = [];
            if (a.entry) {
                out.push({ text: a.windows.length ? "New Window" : "Open", run: () => root.launch(a) });
                out.push({ text: a.pinned ? "Remove from Dock" : "Keep in Dock", run: () => root.togglePin(a.key) });
            }
            if (a.windows.length) out.push({ text: "Quit", run: () => root.quit(a) });
            return out;
        }

        Rectangle {
            id: menuBox
            // Menu coords are in the dock window; it sits at the screen bottom.
            x: root.menuX - width / 2
            y: menu.height - panel.height + root.menuY - height
            width: Math.max(160, menuCol.implicitWidth + 12)
            height: menuCol.implicitHeight + 12
            radius: 10
            color: Qt.alpha(Color.background, 0.94)
            border.color: Qt.alpha(Color.foreground, 0.16)
            border.width: 1

            Column {
                id: menuCol
                x: 6
                y: 6
                width: parent.width - 12

                Text {
                    text: root.menuSlot ? root.menuSlot.name : ""
                    color: Qt.alpha(Color.foreground, 0.55)
                    font.pixelSize: 12
                    leftPadding: 10
                    topPadding: 3
                    bottomPadding: 5
                }

                Repeater {
                    model: menu.items

                    Rectangle {
                        required property var modelData
                        width: menuCol.width
                        height: 28
                        radius: 6
                        color: rowMouse.containsMouse ? Qt.alpha(Color.accent, 0.85) : "transparent"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            text: parent.modelData.text
                            color: rowMouse.containsMouse ? Color.background : Color.foreground
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const run = parent.modelData.run;
                                root.menuSlot = null;
                                run();
                            }
                        }
                    }
                }
            }
        }
    }
}
