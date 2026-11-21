//@ pragma UseQApplication
//@ pragma RespectSystemStyle
// Minimal shell: control center only (ported subset of hyprland-cachyos-rice).
//
//   qs -c rice-cc ipc call controlcenter toggle
//   qs -c rice-cc ipc call controlcenter page wifi|ethernet|sound
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shell

    ControlCenter { id: cc }
    Bar {
        cc: cc
        notifs: notifs
    }
    Osd {}
    NotificationPopups {}
    NotificationCenter { id: notifs }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { cc.toggle() }
        function open(): void { cc.show() }
        function close(): void { cc.close() }
        function page(name: string): void { cc.show(); cc.page = name }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { notifs.toggle() }
        function open(): void { notifs.show() }
        function close(): void { notifs.close() }
        function clear(): void { NotifService.clear() }
        function toggleDnd(): void { NotifService.dnd = !NotifService.dnd }
    }
}
