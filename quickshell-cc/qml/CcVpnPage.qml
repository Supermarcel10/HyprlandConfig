// Control centre · VPN: profiles from NetworkManager (nmcli - the
// Quickshell Networking service does not model VPN), connect/disconnect.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page

    property var cc

    spacing: 12

    CcPageHeader {
        Layout.fillWidth: true
        title: "VPN"
        onBack: page.cc.page = "main"
    }

    Text {
        Layout.leftMargin: 4
        text: "VPN connections"
        color: Theme.on_surface_variant
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Text {
        visible: page.cc.vpnProfiles.length === 0
        Layout.leftMargin: 4
        text: "No VPN profiles - add one with nm-connection-editor"
        color: Theme.on_surface_variant
        font.family: Theme.font
        font.pixelSize: 13
    }

    Repeater {
        model: page.cc.vpnProfiles

        CcRow {
            required property var modelData
            readonly property bool isConnected: page.cc.vpnActive.indexOf(modelData) >= 0
            readonly property bool isBusy: page.cc.vpnBusy === modelData

            icon: "lock"
            title: modelData
            highlighted: isConnected
            busy: isBusy
            subtitle: isBusy ? "Connecting…"
                : isConnected ? "Connected" : "Disconnected"
            actionIcon: isConnected ? "x" : "check"
            onActionClicked: {
                if (isConnected)
                    page.cc.vpnDisconnect(modelData)
                else
                    page.cc.vpnConnect(modelData)
            }
        }
    }
}
