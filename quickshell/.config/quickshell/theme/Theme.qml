pragma Singleton
import QtQuick

QtObject {
    // Surface & background colors
    readonly property color bg: "#000000"
    readonly property color launcherBg: "#0d0d0d"
    readonly property color surface: "#141414"
    readonly property color fg: "#ffffff"
    readonly property color fgDim: "#888888"
    readonly property color border: "#333333"
    readonly property color accent: "#4c7899"
    readonly property color accentDim: Qt.rgba(0.298, 0.471, 0.600, 0.16)

    // Workspace state colors
    readonly property color workspaceFocused: "#64727D"
    readonly property color workspaceUrgent: "#eb4d4b"
    readonly property color panelBorder: Qt.rgba(0.392, 0.447, 0.490, 0.500)

    // Power profile colors
    readonly property color powerPerformance: "#f53c3c"
    readonly property color powerBalanced: "#2980b9"
    readonly property color powerSaver: "#2ecc71"

    // Component state colors
    readonly property color audioMutedBg: "#90b1b1"
    readonly property color audioMutedFg: "#2a5c45"
    readonly property color idleInhibitorActiveBg: "#ecf0f1"
    readonly property color idleInhibitorActiveFg: "#2d3436"
    readonly property color todayBg: "#26A65B"
    readonly property color todayFg: "#000000"
    readonly property color criticalBg: "#900000"
    readonly property color criticalBorder: "#ff0000"

    // Fonts
    readonly property string fontFamily: "Titillium Web"
    readonly property string fontFamilyIconFree: "Font Awesome 7 Free"
    readonly property string fontFamilyIconBrands: "Font Awesome 7 Brands"
    readonly property string fontFamilyMono: "JetBrains Mono"

    readonly property int panelFontSizePt: 12
    readonly property int panelFontWeight: Font.DemiBold
    readonly property int panelIconSizePx: 15

    readonly property int launcherFontSizePt: 10
    readonly property int launcherFontWeight: Font.Normal
    readonly property int launcherIconSizePx: 15

    readonly property int notificationFontSizePt: 12
    readonly property int notificationIconSizePx: 32

    // Sizing & Geometry
    readonly property int panelHeight: 31
    readonly property int panelSpacing: 2

    readonly property int launcherWidth: 480
    readonly property int launcherRadius: 12
    readonly property int launcherBorderWidth: 2
    readonly property int launcherPadding: 6
    readonly property int launcherRowRadius: 4
    readonly property int launcherMaxResults: 12

    readonly property int osdWidth: 400
    readonly property int osdHeight: 32
    readonly property int osdBorderWidth: 2
}
