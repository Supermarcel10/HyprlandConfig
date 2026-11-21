import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import QtQuick.Controls.impl

Scope {
    id: root

    property var cc: null
    property var notifs: null

    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/rice"

    component Pill: Rectangle {
        id: pill
        default property alias content: inner.data
        property int pad: 8
        property int barH: 32
        property bool clickable: false
        property int buttons: Qt.LeftButton
        readonly property bool hovered: hover.containsMouse
        signal clicked(var event)
        signal wheeled(var event)
        color: Theme.alpha(Theme.surface, 0.85)
        border.width: 1
        border.color: Theme.alpha(Theme.primary, 0.45)
        radius: 18
        Layout.preferredHeight: barH
        implicitWidth: Math.max(inner.implicitWidth + pad * 2, barH)
        RowLayout {
            id: inner
            anchors.fill: parent
            anchors.leftMargin: pill.pad
            anchors.rightMargin: pill.pad
            spacing: 6
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            enabled: pill.clickable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: pill.buttons
            onClicked: e => pill.clicked(e)
            onWheel: e => pill.wheeled(e)
        }
    }

    component BarIcon: LucideIcon {
        size: 16
        color: Theme.primary
    }

    component BarText: Text {
        color: Theme.primary
        font.family: Theme.font
        font.pixelSize: 13
    }

    component Clickable: MouseArea {
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }

    property real cpuUsage: 0
    property var lastCpu: null
    property string memUsed: ""
    property string gpuText: ""
    property bool gpuHot: false
    property string netState: "down"
    property int recStart: 0
    property int now: 0
    property bool sharing: false
    property real sharingSince: 0

    readonly property string recElapsed: root.fmtDur(Math.max(0, root.now - root.recStart))
    readonly property string shareElapsed: root.fmtDur(Math.max(0, root.now - root.sharingSince))

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property var song: {
        const ps = Mpris.players.values;
        const live = p => p.trackTitle && (p.playbackState === MprisPlaybackState.Playing || p.playbackState === MprisPlaybackState.Paused);
        const isSone = p => (p.busName || "").toLowerCase().indexOf("sone") >= 0;
        const sone = ps.find(p => isSone(p) && live(p));
        if (sone)
            return root.fmtSong(sone);
        const playing = ps.find(p => live(p) && p.playbackState === MprisPlaybackState.Playing);
        if (playing)
            return root.fmtSong(playing);
        const paused = ps.find(p => live(p));
        return paused ? root.fmtSong(paused) : null;
    }

    function fmtDur(s) {
        const str = Math.floor(s / 60) + ":" + String(Math.floor(s % 60)).padStart(2, "0");
        return str.padEnd(5, " ");
    }

    function padPctStr(s) {
        const m = /^(\d+)%$/.exec(s.trim());
        return m ? (m[1] + "%").padEnd(4, " ") : s;
    }

    function fmtSong(p) {
        let label = p.trackTitle + (p.trackArtist ? " · " + p.trackArtist : "");
        if (label.length > 44)
            label = label.slice(0, 43) + "…";
        return { text: label, playing: p.playbackState === MprisPlaybackState.Playing };
    }

    function parseStat(t) {
        const line = t.split("\n").find(l => l.indexOf("cpu ") === 0);
        if (!line)
            return;
        const f = line.trim().split(/\s+/).slice(1).map(Number);
        const idle = f[3] + f[4];
        const total = f.reduce((a, b) => a + b, 0);
        if (root.lastCpu) {
            const dt = total - root.lastCpu.total;
            if (dt > 0)
                root.cpuUsage = (1 - (idle - root.lastCpu.idle) / dt) * 100;
        }
        root.lastCpu = { total: total, idle: idle };
    }

    function parseMem(t) {
        const total = /MemTotal:\s+(\d+)/.exec(t);
        const avail = /MemAvailable:\s+(\d+)/.exec(t);
        if (total && avail)
            root.memUsed = (Number((Number(total[1]) - Number(avail[1])) / 1048576).toFixed(1) + "G").padEnd(5, " ");
    }

    function parseNm(t) {
        let s = "down";
        for (const line of t.split("\n")) {
            const parts = line.split(":");
            if (parts[1] !== "connected")
                continue;
            if (parts[0] === "ethernet") {
                s = "eth";
                break;
            }
            if (parts[0] === "wifi")
                s = "wifi";
        }
        root.netState = s;
    }

    function parseRec(t) {
        const v = parseInt(t.trim(), 10);
        root.recStart = isNaN(v) ? 0 : v;
    }

    function onShareExit(code) {
        const live = code === 0;
        if (live && !root.sharing)
            root.sharingSince = root.now;
        if (!live)
            root.sharingSince = 0;
        root.sharing = live;
    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(o => o)
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    FileView {
        id: statView
        path: "/proc/stat"
        onLoaded: root.parseStat(text())
    }

    FileView {
        id: memView
        path: "/proc/meminfo"
        onLoaded: root.parseMem(text())
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statView.reload();
            memView.reload();
            if (!gpuProc.running)
                gpuProc.running = true;
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!nmProc.running)
                nmProc.running = true;
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!shareProc.running)
                shareProc.running = true;
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Math.floor(Date.now() / 1000);
            if (!recProc.running)
                recProc.running = true;
        }
    }

    Process {
        id: gpuProc
        command: ["rice-gpu"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    root.gpuText = o.text || "";
                    root.gpuHot = o.class === "hot";
                } catch (e) {}
            }
        }
    }

    Process {
        id: nmProc
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.parseNm(text)
        }
    }

    Process {
        id: shareProc
        command: ["sh", "-c", "pw-dump 2>/dev/null | jq -e '[.[] | select(.type==\"PipeWire:Interface:Node\") | .info.props | select(.[\"media.class\"]==\"Stream/Input/Video\" and .[\"node.driver\"] != true)] | length > 0' >/dev/null"]
        onExited: (code, status) => root.onShareExit(code)
    }

    Process {
        id: recProc
        command: ["cat", root.cacheDir + "/recording"]
        stdout: StdioCollector {
            onStreamFinished: root.parseRec(text)
        }
        onExited: (code, status) => {
            if (code !== 0)
                root.recStart = 0;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            margins {
                top: 5
                left: 5
                right: 5
            }
            implicitHeight: 36
            exclusionMode: ExclusionMode.Auto
            color: "transparent"
            WlrLayershell.namespace: "rice-bar"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property string screenName: modelData.name
            readonly property var spaces: {
                const all = Hyprland.workspaces.values.filter(w => w.id > 0);
                const here = all.filter(w => w.monitor && w.monitor.name === screenName);
                const list = here.length ? here : all;
                return list.slice().sort((a, b) => a.id - b.id);
            }
            readonly property var hlMon: Hyprland.monitors.values.find(m => m.name === screenName)

            function winCount(id) {
                return Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === id).length;
            }

            Item {
                anchors.fill: parent

                RowLayout {
                    id: leftModules
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Pill {
                        Item {
                            implicitWidth: 20
                            implicitHeight: 20
                            BarIcon {
                                anchors.centerIn: parent
                                icon: "layout-grid"
                            }
                            Clickable {
                                anchors.fill: parent
                                onClicked: Quickshell.execDetached(["uwsm", "app", "--", "wofi", "--show", "drun"])
                            }
                        }
                        Item {
                            implicitWidth: 20
                            implicitHeight: 20
                            BarIcon {
                                anchors.centerIn: parent
                                icon: "clipboard-list"
                            }
                            Clickable {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: e => Quickshell.execDetached(e.button === Qt.RightButton ? ["rice-clipboard", "--wipe"] : ["rice-clipboard"])
                            }
                        }
                    }

                    Pill {
                        pad: 4
                        Repeater {
                            model: spaces
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool active: hlMon && hlMon.activeWorkspace && hlMon.activeWorkspace.id === modelData.id
                                readonly property bool empty: winCount(modelData.id) === 0
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 26
                                radius: 13
                                color: active ? Theme.primary : wsArea.containsMouse ? Theme.alpha(Theme.primary, 0.14) : "transparent"
                                BarText {
                                    anchors.centerIn: parent
                                    text: modelData.id
                                    color: active ? Theme.on_primary : empty ? Theme.on_surface_variant : Theme.primary
                                    font.weight: active ? Font.Bold : Font.Normal
                                }
                                MouseArea {
                                    id: wsArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch("workspace " + modelData.id)
                                    onWheel: e => {
                                        Hyprland.dispatch("workspace " + (e.angleDelta.y > 0 ? "e-1" : "e+1"));
                                        e.accepted = true;
                                    }
                                }
                            }
                        }
                    }

                    Pill {
                        RowLayout {
                            spacing: 3
                            BarIcon {
                                icon: "cpu"
                            }
                            BarText {
                                text: (Math.round(root.cpuUsage) + "%").padEnd(4, " ")
                            }
                        }
                        RowLayout {
                            spacing: 3
                            BarIcon {
                                icon: "gpu"
                            }
                            BarText {
                                text: root.padPctStr(root.gpuText)
                                color: root.gpuHot ? Theme.error : Theme.primary
                            }
                        }
                        RowLayout {
                            spacing: 3
                            BarIcon {
                                icon: "memory-stick"
                            }
                            BarText {
                                text: root.memUsed
                            }
                        }
                    }
                }

                RowLayout {
                    id: centerModules
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Pill {
                        BarText {
                            text: Qt.formatDateTime(clock.date, "ddd dd MMM  HH:mm:ss t")
                            font.weight: Font.Bold
                        }
                    }

                    Pill {
                        id: musicPill
                        clickable: true
                        buttons: Qt.LeftButton | Qt.RightButton
                        onClicked: e => Quickshell.execDetached(e.button === Qt.RightButton ? ["rice-media", "next"] : ["rice-media", "play-pause"])
                        BarIcon {
                            icon: "music"
                            size: 12
                        }
                        BarText {
                            visible: musicPill.hovered && root.song !== null
                            text: root.song ? root.song.text : ""
                            opacity: root.song && root.song.playing ? 1 : 0.6
                            Layout.maximumWidth: 340
                            elide: Text.ElideRight
                        }
                    }
                }

                RowLayout {
                    id: rightModules
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Pill {
                        clickable: true
                        buttons: Qt.LeftButton | Qt.RightButton
                        onClicked: e => Quickshell.execDetached(e.button === Qt.RightButton ? ["rice-record", "--area"] : ["rice-record"])
                        BarText {
                            readonly property bool rec: root.recStart > 0
                            visible: text !== ""
                            text: rec ? "● " + root.recElapsed : root.sharing ? "◉ " + root.shareElapsed + " sharing" : ""
                            color: rec ? Theme.error : Theme.tertiary
                            font.weight: Font.Bold
                        }
                        BarIcon {
                            visible: root.recStart === 0 && !root.sharing
                            icon: "disc"
                            color: Theme.on_surface_variant
                            opacity: 0.6
                        }
                    }

                    Pill {
                        clickable: true
                        buttons: Qt.LeftButton | Qt.RightButton
                        onClicked: e => {
                            if (e.button === Qt.RightButton)
                                NotifService.dnd = !NotifService.dnd;
                            else if (root.notifs)
                                root.notifs.toggle();
                        }
                        BarIcon {
                            icon: NotifService.dnd ? "bell-off" : NotifService.count > 0 ? "bell-ring" : "bell"
                            opacity: NotifService.dnd || NotifService.count === 0 ? 0.6 : 1
                        }
                    }

                    Pill {
                        clickable: true
                        buttons: Qt.LeftButton | Qt.RightButton
                        onClicked: e => {
                            if (e.button === Qt.RightButton)
                                Quickshell.execDetached(["nm-connection-editor"]);
                            else if (root.cc) {
                                root.cc.show();
                                root.cc.page = root.netState === "eth" ? "ethernet" : "wifi";
                            }
                        }
                        BarIcon {
                            icon: root.netState === "wifi" ? "wifi" : root.netState === "eth" ? "ethernet-port" : "wifi-off"
                            color: root.netState === "down" ? Theme.error : Theme.primary
                        }
                    }

                    Pill {
                        clickable: true
                        buttons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: e => {
                            if (!root.sink || !root.sink.audio)
                                return;
                            if (e.button === Qt.MiddleButton)
                                Quickshell.execDetached(["pavucontrol"]);
                            else if (e.button === Qt.RightButton)
                                root.sink.audio.muted = !root.sink.audio.muted;
                            else if (root.cc) {
                                root.cc.show();
                                root.cc.page = "sound";
                            }
                        }
                        onWheeled: e => {
                            if (root.sink && root.sink.audio)
                                root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
                            e.accepted = true;
                        }
                        BarIcon {
                            icon: !root.sink || !root.sink.audio ? "volume-x" : root.sink.audio.muted ? "volume-x" : root.sink.audio.volume > 0.66 ? "volume-2" : root.sink.audio.volume > 0.33 ? "volume-1" : "volume"
                            opacity: root.sink && root.sink.audio && root.sink.audio.muted ? 0.5 : 1
                        }
                        BarText {
                            visible: root.sink && root.sink.audio && !root.sink.audio.muted
                            text: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) + "%" : ""
                        }
                    }

                    Pill {
                        clickable: true
                        onClicked: {
                            if (root.source && root.source.audio)
                                root.source.audio.muted = !root.source.audio.muted;
                        }
                        onWheeled: e => {
                            if (root.source && root.source.audio)
                                root.source.audio.volume = Math.max(0, Math.min(1, root.source.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
                            e.accepted = true;
                        }
                        BarIcon {
                            icon: root.source && root.source.audio && root.source.audio.muted ? "mic-off" : "mic"
                            opacity: root.source && root.source.audio && root.source.audio.muted ? 0.5 : 1
                        }
                    }

                    Pill {
                        visible: trayRep.count > 0
                        Repeater {
                            id: trayRep
                            model: SystemTray.items
                            delegate: Item {
                                required property SystemTrayItem modelData
                                implicitWidth: 22
                                implicitHeight: 22
                                IconImage {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    source: parent.modelData.icon
                                }
                                MouseArea {
                                    id: trayMouse
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: e => {
                                        const item = parent.modelData;
                                        if (e.button === Qt.LeftButton && !item.onlyMenu)
                                            item.activate();
                                        else if (e.button === Qt.MiddleButton)
                                            item.secondaryActivate();
                                        else if (item.hasMenu) {
                                            // display() positions the platform menu itself;
                                            // coordinates are relative to the bar window.
                                            const p = trayMouse.mapToItem(barWindow.contentItem, e.x, e.y);
                                            item.display(barWindow, p.x, p.y);
                                        } else
                                            item.secondaryActivate();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
