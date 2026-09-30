//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    property bool expanded: Quickshell.env("AI_USAGE_OPEN") === "1"
    property bool loading: false
    property bool parsedCurrentRequest: false
    property string backendError: ""
    property var providers: ({})
    property double nowMs: Date.now()
    property date lastUpdated: new Date(0)
    // Unmapping and remapping the pill puts it back on top of the Top layer.
    property bool pillMapped: true
    property var colors: ({
        background: "#131312",
        on_background: "#e4e2df",
        on_surface_variant: "#c5c7bf",
        outline: "#8f9189",
        primary: "#c0cab6",
        surface_container_low: "#1b1c1a",
        surface_container: "#1f201e",
        surface_container_high: "#2a2a28",
        surface_container_highest: "#353533",
        outline_variant: "#454841",
        error: "#ffb4ab",
        error_container: "#93000a",
        on_error_container: "#ffdad6"
    })

    readonly property string home: Quickshell.env("HOME")
    readonly property string fontFamily: "Google Sans Flex"
    readonly property string monoFamily: "JetBrains Mono NF"
    readonly property string iconFamily: "Material Symbols Rounded"
    readonly property var providerIds: ["claude", "codex"]
    readonly property color warningColor: "#f3b562"
    // end4 bar geometry: 40 px tall, groups inset by 4 px, 12 px radius.
    readonly property int barHeight: 40
    readonly property int popupWidth: 372
    // Position immediately after end4's centred controls.
    // Keep this as one obvious knob for layouts with a different bar width.
    property int compactBarOffsetFromCenter: 490

    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
    readonly property int pillX: Math.round((targetScreen?.width ?? 1920) / 2 + compactBarOffsetFromCenter)

    function refresh() {
        if (usageProcess.running)
            return;
        root.loading = true;
        root.parsedCurrentRequest = false;
        root.backendError = "";
        usageProcess.running = true;
    }

    function refreshIfStale() {
        if (Date.now() - root.lastUpdated.getTime() > 60000)
            root.refresh();
    }

    function restackPill() {
        if (!root.pillMapped)
            return;
        root.pillMapped = false;
        restackTimer.restart();
    }

    function consumeOutput(text) {
        if (!text || text.trim().length === 0)
            return;

        try {
            const payload = JSON.parse(text);
            if (!Array.isArray(payload))
                throw new Error("unexpected JSON shape");

            const nextProviders = {};
            for (const entry of payload) {
                if (entry && entry.provider)
                    nextProviders[entry.provider] = entry;
            }
            root.providers = nextProviders;
            root.lastUpdated = new Date();
            root.parsedCurrentRequest = true;
            root.backendError = "";
        } catch (error) {
            root.backendError = "Could not parse CodexBar output";
            console.warn("[ai-usage] JSON parse failed:", error);
        }
    }

    function providerData(providerId) {
        return root.providers[providerId] ?? null;
    }

    function providerName(providerId) {
        return providerId === "claude" ? "Claude" : "Codex";
    }

    function providerPlan(providerId) {
        const data = root.providerData(providerId);
        return data?.usage?.identity?.loginMethod ?? data?.usage?.loginMethod ?? "";
    }

    function providerError(providerId) {
        const data = root.providerData(providerId);
        if (!data)
            return root.backendError || (root.loading ? "" : "No data yet");
        const message = data.error?.message ?? "";
        const lower = message.toLowerCase();
        if (lower.includes("not installed"))
            return "Install codexbar-cli to see usage";
        if (lower.includes("expired") || lower.includes("invalid") || lower.includes("login"))
            return `Session expired — run ${providerId} login`;
        return message;
    }

    function windowLabel(key, label, minutes) {
        const normalized = (label ?? "").toLowerCase();
        if (normalized === "weekly" || normalized === "week")
            return "Weekly";
        if (normalized === "session" || normalized.includes("5-hour") || normalized.includes("five hour"))
            return "5-hour session";
        if (label)
            return label;
        if (minutes > 0 && minutes <= 360)
            return "5-hour session";
        if (minutes > 0 && minutes <= 10080)
            return "Weekly";
        return key === "primary" ? "Session" : key === "secondary" ? "Weekly" : "Limit";
    }

    function windowsFor(providerId) {
        const data = root.providerData(providerId);
        if (!data?.usage)
            return [];

        const result = [];
        for (const key of ["primary", "secondary", "tertiary"]) {
            const windowData = data.usage[key];
            if (!windowData)
                continue;

            const pace = data.pace?.[key] ?? null;
            result.push({
                key: key,
                label: root.windowLabel(key, data.rateWindowLabels?.[key], windowData.windowMinutes ?? 0),
                usedPercent: Math.max(0, Math.min(100, windowData.usedPercent ?? 0)),
                resetsAt: windowData.resetsAt ?? "",
                expectedPercent: pace?.expectedUsedPercent ?? -1,
                paceText: root.paceText(pace),
                paceWarning: pace ? pace.willLastToReset === false : false
            });
        }
        return result;
    }

    // CodexBar summaries look like "On pace | Expected 10% used | Runs out in 5d 17h".
    function paceText(pace) {
        if (!pace?.summary)
            return "";
        const parts = pace.summary.split("|").map(part => part.trim());
        if (pace.willLastToReset === false && parts.length > 2)
            return parts[2];
        return parts[0];
    }

    function primaryPercent(providerId) {
        const windows = root.windowsFor(providerId);
        return windows.length > 0 ? windows[0].usedPercent : -1;
    }

    function levelColor(value, accent) {
        if (value >= 90)
            return root.colors.error;
        if (value >= 75)
            return root.warningColor;
        return accent;
    }

    function formatDuration(totalMinutes) {
        if (totalMinutes < 60)
            return `${totalMinutes}m`;
        const hours = Math.floor(totalMinutes / 60);
        if (hours < 24)
            return `${hours}h ${totalMinutes % 60}m`;
        return `${Math.floor(hours / 24)}d ${hours % 24}h`;
    }

    function formatReset(isoTime) {
        // Make this binding depend on the minute timer.
        const ignored = root.nowMs;
        if (!isoTime)
            return "Reset time unknown";
        const resetDate = new Date(isoTime);
        const remaining = resetDate.getTime() - Date.now();
        if (!Number.isFinite(remaining))
            return "Reset time unknown";
        if (remaining <= 0)
            return "Resetting now";

        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        const clock = Qt.formatTime(resetDate, "HH:mm");
        const at = remaining < 86400000 ? clock : `${days[resetDate.getDay()]} ${clock}`;
        return `Resets in ${root.formatDuration(Math.ceil(remaining / 60000))} · ${at}`;
    }

    function providerAccent(providerId) {
        return providerId === "claude" ? "#d97757" : "#10a37f";
    }

    function providerIcon(providerId) {
        return Quickshell.iconPath(providerId === "claude" ? "claude-desktop" : "codex-desktop");
    }

    function applyPalette() {
        const text = paletteFile.text();
        if (!text || text.trim().length === 0)
            return;
        try {
            root.colors = Object.assign({}, root.colors, JSON.parse(text));
        } catch (error) {
            console.warn("[ai-usage] Could not load end4 palette:", error);
        }
    }

    Component.onCompleted: root.refresh()

    Timer {
        interval: 300000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
    }

    Timer {
        id: restackTimer
        interval: 120
        onTriggered: root.pillMapped = true
    }

    // Both this pill and the end4 bar live on the Top layer, where the most
    // recently mapped surface is drawn last. The bar is recreated on startup,
    // after unlocking and on shell reloads, so jump back above it each time.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openlayer" && event.data.trim() === "quickshell:bar")
                root.restackPill();
        }
    }

    FileView {
        id: paletteFile
        path: `${root.home}/.local/state/quickshell/user/generated/colors.json`
        watchChanges: true
        onFileChanged: reload()
        onLoadedChanged: root.applyPalette()
    }

    Process {
        id: usageProcess
        command: [Quickshell.shellPath("backend.sh")]
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: root.consumeOutput(outputCollector.text)
        }
        onExited: (exitCode, exitStatus) => {
            root.loading = false;
            if (!root.parsedCurrentRequest && !root.backendError)
                root.backendError = exitCode === 124 ? "CodexBar timed out" : "CodexBar exited with an error";
        }
    }

    IpcHandler {
        target: "aiUsage"

        function toggle(): void {
            root.expanded = !root.expanded;
            if (root.expanded)
                root.refreshIfStale();
        }

        function open(): void {
            root.expanded = true;
            root.refreshIfStale();
        }

        function close(): void {
            root.expanded = false;
        }

        function refresh(): void {
            root.refresh();
        }
    }

    HyprlandFocusGrab {
        active: root.expanded && popup.visible
        windows: [popup, pill]
        onCleared: root.expanded = false
    }

    // Compact pill that sits inside the bar.
    PanelWindow {
        id: pill

        screen: root.targetScreen
        visible: root.pillMapped
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        implicitWidth: pillBody.implicitWidth
        implicitHeight: root.barHeight

        WlrLayershell.namespace: "quickshell:aiUsage"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            left: true
            bottom: true
        }
        margins.left: root.pillX

        mask: Region { item: pillBody }

        Rectangle {
            id: pillBody

            anchors {
                fill: parent
                topMargin: 4
                bottomMargin: 4
            }
            implicitWidth: pillRow.implicitWidth + 16
            radius: 12
            color: root.expanded
                ? root.colors.surface_container_high
                : pillMouse.containsMouse ? root.colors.surface_container : root.colors.surface_container_low

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 10
                opacity: root.loading && root.lastUpdated.getTime() === 0 ? 0.5 : 1

                Repeater {
                    model: root.providerIds
                    delegate: PillProvider {
                        required property string modelData
                        providerId: modelData
                    }
                }
            }

            MouseArea {
                id: pillMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: event => {
                    if (event.button === Qt.RightButton) {
                        root.refresh();
                    } else {
                        root.expanded = !root.expanded;
                        if (root.expanded)
                            root.refreshIfStale();
                    }
                }
            }
        }
    }

    // Detail popup. Overlay so that it opens above fullscreen windows too.
    PanelWindow {
        id: popup

        property real reveal: root.expanded ? 1 : 0
        Behavior on reveal {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        screen: root.targetScreen
        visible: root.expanded || reveal > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        implicitWidth: root.popupWidth + 2 * shadowMargin
        implicitHeight: card.implicitHeight + 2 * shadowMargin

        readonly property int shadowMargin: 16

        WlrLayershell.namespace: "quickshell:aiUsagePopup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            left: true
            bottom: true
        }
        margins {
            left: Math.max(0, Math.min(root.pillX - shadowMargin, (root.targetScreen?.width ?? 1920) - implicitWidth - 4))
            bottom: root.barHeight + 6 - shadowMargin
        }

        mask: Region { item: card }

        Item {
            id: sheet
            x: popup.shadowMargin
            y: popup.shadowMargin
            width: card.width
            height: card.height
            opacity: popup.reveal
            transform: Translate { y: (1 - popup.reveal) * 12 }

            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                blur: 18
                spread: 1
                offset: Qt.vector2d(0, 3)
                color: Qt.rgba(0, 0, 0, 0.45)
            }

            Rectangle {
                id: card

                width: root.popupWidth
                implicitHeight: cardColumn.implicitHeight + 28
                height: implicitHeight
                radius: 22
                color: root.colors.surface_container
                border.width: 1
                border.color: Qt.alpha(root.colors.outline_variant, 0.6)

                focus: root.expanded
                Keys.onEscapePressed: root.expanded = false
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_R || event.key === Qt.Key_F5) {
                        root.refresh();
                        event.accepted = true;
                    }
                }

                ColumnLayout {
                    id: cardColumn
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 14
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        spacing: 6

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            UiText {
                                Layout.fillWidth: true
                                text: "AI usage"
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            UiText {
                                Layout.fillWidth: true
                                text: root.loading
                                    ? "Refreshing…"
                                    : root.lastUpdated.getTime() > 0
                                        ? `Updated ${Qt.formatTime(root.lastUpdated, "HH:mm")}`
                                        : "Waiting for data"
                                color: root.colors.on_surface_variant
                                font.pixelSize: 11
                            }
                        }

                        IconButton {
                            icon: "refresh"
                            spinning: root.loading
                            onClicked: root.refresh()
                        }
                        IconButton {
                            icon: "close"
                            onClicked: root.expanded = false
                        }
                    }

                    Repeater {
                        model: root.providerIds
                        delegate: ProviderCard {
                            required property string modelData
                            Layout.fillWidth: true
                            providerId: modelData
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        spacing: 6

                        UiText {
                            Layout.fillWidth: true
                            text: "Tick marks expected usage · refreshes every 5 min"
                            color: root.colors.outline
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        Keycap { text: "Super" }
                        Keycap { text: "U" }
                    }
                }
            }
        }
    }

    component UiText: Text {
        color: root.colors.on_background
        font.family: root.fontFamily
        font.pixelSize: 12
    }

    component Symbol: Text {
        property real fill: 0
        property real iconSize: 18
        color: root.colors.on_surface_variant
        renderType: Text.NativeRendering
        font.family: root.iconFamily
        font.pixelSize: iconSize
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({ "FILL": fill, "opsz": iconSize })
    }

    component Keycap: Rectangle {
        property alias text: keyLabel.text
        implicitWidth: keyLabel.implicitWidth + 10
        implicitHeight: 18
        radius: 5
        color: root.colors.surface_container_high
        border.width: 1
        border.color: root.colors.outline_variant

        Text {
            id: keyLabel
            anchors.centerIn: parent
            color: root.colors.on_surface_variant
            font.family: root.monoFamily
            font.pixelSize: 9
        }
    }

    component IconButton: Rectangle {
        id: iconButton
        property string icon
        property bool spinning: false
        signal clicked()

        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: buttonMouse.pressed
            ? root.colors.surface_container_highest
            : buttonMouse.containsMouse ? root.colors.surface_container_high : "transparent"

        Symbol {
            id: buttonIcon
            anchors.centerIn: parent
            text: iconButton.icon
            iconSize: 20

            RotationAnimation on rotation {
                running: iconButton.spinning
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
                onRunningChanged: if (!running) buttonIcon.rotation = 0
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.clicked()
        }
    }

    component ProviderCard: Rectangle {
        id: providerCard

        required property string providerId
        readonly property var usageWindows: root.windowsFor(providerId)
        readonly property string errorText: root.providerError(providerId)
        readonly property string plan: root.providerPlan(providerId)
        readonly property color accent: root.providerAccent(providerId)

        color: root.colors.surface_container_low
        radius: 16
        implicitHeight: providerColumn.implicitHeight + 26

        ColumnLayout {
            id: providerColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 13
            }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 10
                    color: Qt.alpha(providerCard.accent, 0.16)

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 22
                        source: root.providerIcon(providerCard.providerId)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    UiText {
                        Layout.fillWidth: true
                        text: root.providerName(providerCard.providerId)
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    UiText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: providerCard.plan
                        color: root.colors.on_surface_variant
                        font.pixelSize: 11
                    }
                }

                UiText {
                    visible: providerCard.usageWindows.length > 0
                    text: `${Math.round(providerCard.usageWindows[0]?.usedPercent ?? 0)}%`
                    color: root.levelColor(providerCard.usageWindows[0]?.usedPercent ?? 0, providerCard.accent)
                    font.family: root.monoFamily
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: providerCard.errorText.length > 0
                implicitHeight: errorRow.implicitHeight + 16
                radius: 10
                color: Qt.alpha(root.colors.error_container, 0.28)

                RowLayout {
                    id: errorRow
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        right: parent.right
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 8

                    Symbol {
                        text: "error"
                        fill: 1
                        color: root.colors.error
                        iconSize: 16
                    }
                    UiText {
                        Layout.fillWidth: true
                        text: providerCard.errorText
                        color: root.colors.on_error_container
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }

            Repeater {
                model: providerCard.usageWindows
                delegate: ColumnLayout {
                    id: windowRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        UiText {
                            Layout.fillWidth: true
                            text: windowRow.modelData.label
                            color: root.colors.on_surface_variant
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        UiText {
                            text: `${Math.round(windowRow.modelData.usedPercent)}%`
                            font.family: root.monoFamily
                            font.pixelSize: 11
                        }
                    }

                    UsageBar {
                        Layout.fillWidth: true
                        value: windowRow.modelData.usedPercent
                        expected: windowRow.modelData.expectedPercent
                        accent: providerCard.accent
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        UiText {
                            Layout.fillWidth: true
                            text: root.formatReset(windowRow.modelData.resetsAt)
                            color: root.colors.outline
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        UiText {
                            visible: text.length > 0
                            text: windowRow.modelData.paceText
                            color: windowRow.modelData.paceWarning ? root.warningColor : root.colors.outline
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    component PillProvider: RowLayout {
        id: pillProvider

        required property string providerId
        readonly property real percent: root.primaryPercent(providerId)
        readonly property bool failed: percent < 0 && root.providerError(providerId).length > 0
        readonly property color levelColor: root.levelColor(percent, root.providerAccent(providerId))

        spacing: 5

        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22

            UsageRing {
                anchors.fill: parent
                value: Math.max(0, pillProvider.percent)
                accent: pillProvider.levelColor
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: 13
                source: root.providerIcon(pillProvider.providerId)
                opacity: pillProvider.failed ? 0.45 : 1
            }
        }

        Item {
            Layout.preferredWidth: percentMetrics.width
            Layout.preferredHeight: percentText.implicitHeight

            TextMetrics {
                id: percentMetrics
                text: "100%"
                font: percentText.font
            }

            Symbol {
                anchors.centerIn: parent
                visible: pillProvider.failed
                text: "error"
                fill: 1
                color: root.colors.error
                iconSize: 15
            }

            UiText {
                id: percentText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !pillProvider.failed
                text: pillProvider.percent >= 0 ? `${Math.round(pillProvider.percent)}%` : "—"
                color: pillProvider.percent >= 75 ? pillProvider.levelColor : root.colors.on_surface_variant
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }
    }

    component UsageRing: Item {
        id: ring
        required property real value
        required property color accent
        property real lineWidth: 2.5
        readonly property real arcRadius: Math.min(width, height) / 2 - lineWidth / 2

        property real animatedValue: value
        Behavior on animatedValue { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.alpha(root.colors.outline_variant, 0.9)
                strokeWidth: ring.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.arcRadius
                    radiusY: ring.arcRadius
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            ShapePath {
                strokeColor: ring.animatedValue > 0 ? ring.accent : "transparent"
                strokeWidth: ring.lineWidth
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.arcRadius
                    radiusY: ring.arcRadius
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0, Math.min(100, ring.animatedValue)) / 100
                }
            }
        }
    }

    component UsageBar: Item {
        id: usageBar
        required property real value
        required property color accent
        property real expected: -1
        implicitHeight: 8

        property real animatedValue: value
        Behavior on animatedValue { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.alpha(root.colors.outline_variant, 0.7)
        }

        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            width: Math.max(height, parent.width * Math.max(0, Math.min(100, usageBar.animatedValue)) / 100)
            visible: usageBar.value > 0
            radius: height / 2
            color: root.levelColor(usageBar.value, usageBar.accent)
        }

        // Where usage "should" be if spread evenly across the window.
        Rectangle {
            visible: usageBar.expected >= 0
            x: Math.round(usageBar.width * Math.min(100, usageBar.expected) / 100 - width / 2)
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: parent.height + 6
            radius: 1
            color: root.colors.on_background
            opacity: 0.8
        }
    }
}
