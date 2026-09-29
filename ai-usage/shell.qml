//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    property bool expanded: false
    property bool loading: false
    property bool parsedCurrentRequest: false
    property string backendError: ""
    property var providers: ({})
    property double nowMs: Date.now()
    property date lastUpdated: new Date(0)
    property var palette: ({
        background: "#131312",
        on_background: "#e4e2df",
        on_surface_variant: "#c5c7bf",
        primary: "#c0cab6",
        surface_container: "#1f201e",
        surface_container_high: "#2a2a28",
        outline_variant: "#454841",
        error: "#ffb4ab",
        error_container: "#93000a"
    })

    readonly property string home: Quickshell.env("HOME")
    readonly property string fontFamily: "Google Sans Flex"
    readonly property string monoFamily: "JetBrains Mono NF"
    // Position immediately after end4's centred controls on a 1920 px display.
    // Keep this as one obvious knob for layouts with a different bar width.
    property int compactBarOffsetFromCenter: 490

    function refresh() {
        if (usageProcess.running)
            return;
        root.loading = true;
        root.parsedCurrentRequest = false;
        root.backendError = "";
        usageProcess.running = true;
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
            root.backendError = "Не удалось прочитать ответ CodexBar";
            console.warn("[ai-usage] JSON parse failed:", error);
        }
    }

    function providerData(providerId) {
        return root.providers[providerId] ?? null;
    }

    function providerError(providerId) {
        const data = root.providerData(providerId);
        if (!data)
            return root.backendError || (root.loading ? "Обновление…" : "Нет данных");
        const message = data.error?.message ?? "";
        const lower = message.toLowerCase();
        if (lower.includes("not installed"))
            return "Установи codexbar-cli";
        if (lower.includes("expired") || lower.includes("run `claude login`"))
            return "Сессия истекла — выполни claude login";
        return message;
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

            let label = data.rateWindowLabels?.[key] ?? "";
            const normalizedLabel = label.toLowerCase();
            if (normalizedLabel === "weekly" || normalizedLabel === "week")
                label = "Неделя";
            else if (normalizedLabel.includes("5-hour") || normalizedLabel.includes("five hour"))
                label = "5 часов";
            else if (normalizedLabel === "session")
                label = "Сессия";
            if (!label) {
                const minutes = windowData.windowMinutes ?? 0;
                if (minutes > 0 && minutes <= 360)
                    label = "5 часов";
                else if (minutes > 0 && minutes <= 10080)
                    label = "Неделя";
                else
                    label = key === "primary" ? "Сессия" : key === "secondary" ? "Неделя" : "Лимит";
            }

            result.push({
                key: key,
                label: label,
                usedPercent: Math.max(0, Math.min(100, windowData.usedPercent ?? 0)),
                resetsAt: windowData.resetsAt ?? ""
            });
        }
        return result;
    }

    function compactPercent(providerId) {
        const windows = root.windowsFor(providerId);
        if (windows.length === 0)
            return "—";
        return `${Math.round(windows[0].usedPercent)}%`;
    }

    function compactValue(providerId) {
        const windows = root.windowsFor(providerId);
        return windows.length > 0 ? windows[0].usedPercent : 0;
    }

    function formatReset(isoTime) {
        // Make this binding depend on the minute timer.
        const ignored = root.nowMs;
        if (!isoTime)
            return "время сброса неизвестно";
        const remaining = new Date(isoTime).getTime() - Date.now();
        if (!Number.isFinite(remaining))
            return "время сброса неизвестно";
        if (remaining <= 0)
            return "сбрасывается сейчас";

        const totalMinutes = Math.ceil(remaining / 60000);
        if (totalMinutes < 60)
            return `сброс через ${totalMinutes} мин`;
        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        if (hours < 24)
            return `сброс через ${hours} ч ${minutes} мин`;
        const days = Math.floor(hours / 24);
        return `сброс через ${days} д ${hours % 24} ч`;
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
            root.palette = Object.assign({}, root.palette, JSON.parse(text));
        } catch (error) {
            console.warn("[ai-usage] Could not load end4 palette:", error);
        }
    }

    Component.onCompleted: root.refresh()

    Timer {
        interval: 300000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
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
                root.backendError = exitCode === 124 ? "CodexBar не ответил вовремя" : "CodexBar завершился с ошибкой";
        }
    }

    IpcHandler {
        target: "aiUsage"

        function toggle(): void {
            root.expanded = !root.expanded;
            if (root.expanded)
                root.refresh();
        }

        function open(): void {
            root.expanded = true;
            root.refresh();
        }

        function close(): void {
            root.expanded = false;
        }

        function refresh(): void {
            root.refresh();
        }
    }

    PanelWindow {
        id: panel

        screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? null
        visible: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        implicitWidth: root.expanded ? 420 : 156
        implicitHeight: root.expanded ? expandedContent.implicitHeight + 28 : 40

        WlrLayershell.namespace: "quickshell:aiUsage"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            left: !root.expanded
            right: root.expanded
            bottom: true
        }
        margins {
            // The end4 middle section ends about 490 px to the right of the
            // screen centre with the current verbose 1920 px bar layout.
            // Put the compact widget directly after that group.
            left: root.expanded ? 0 : Math.round((panel.screen?.width ?? 1920) / 2 + root.compactBarOffsetFromCenter)
            right: root.expanded ? 10 : 0
            bottom: root.expanded ? 48 : 0
        }

        mask: Region { item: panelCard }

        Behavior on implicitWidth {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on implicitHeight {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: panelCard
            anchors {
                fill: parent
                topMargin: root.expanded ? 0 : 4
                bottomMargin: root.expanded ? 0 : 4
            }
            color: !root.expanded && compactMouse.containsMouse
                ? root.palette.surface_container_high
                : root.palette.surface_container
            border.width: root.expanded ? 1 : 0
            border.color: root.palette.outline_variant
            radius: root.expanded ? 18 : 8
            clip: true

            Behavior on radius { NumberAnimation { duration: 180 } }

            ColumnLayout {
                id: compactContent
                anchors.fill: parent
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                spacing: 0
                visible: !root.expanded
                opacity: visible ? 1 : 0

                CompactProvider {
                    Layout.fillWidth: true
                    providerId: "claude"
                }

                CompactProvider {
                    Layout.fillWidth: true
                    providerId: "codex"
                }
            }

            MouseArea {
                id: compactMouse
                anchors.fill: compactContent
                enabled: !root.expanded
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: event => {
                    if (event.button === Qt.RightButton)
                        root.refresh();
                    else
                        root.expanded = true;
                }
            }

            ColumnLayout {
                id: expandedContent
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 14
                }
                spacing: 10
                visible: root.expanded
                opacity: visible ? 1 : 0

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Claude + Codex"
                        color: root.palette.on_background
                        font.family: root.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: refreshMouse.containsMouse ? root.palette.surface_container_high : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: root.loading ? "…" : "↻"
                            color: root.palette.on_surface_variant
                            font.family: root.fontFamily
                            font.pixelSize: 18
                        }
                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: closeMouse.containsMouse ? root.palette.surface_container_high : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: root.palette.on_surface_variant
                            font.family: root.fontFamily
                            font.pixelSize: 20
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.expanded = false
                        }
                    }
                }

                ProviderCard {
                    Layout.fillWidth: true
                    providerId: "claude"
                    providerName: "Claude"
                }

                ProviderCard {
                    Layout.fillWidth: true
                    providerId: "codex"
                    providerName: "Codex"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.lastUpdated.getTime() > 0
                            ? `Обновлено ${Qt.formatTime(root.lastUpdated, "HH:mm")}`
                            : "Ожидание данных"
                        color: root.palette.on_surface_variant
                        font.family: root.fontFamily
                        font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Super+U"
                        color: root.palette.on_surface_variant
                        font.family: root.monoFamily
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    component ProviderCard: Rectangle {
        id: providerCard

        required property string providerId
        required property string providerName
        readonly property var usageWindows: root.windowsFor(providerId)
        readonly property string errorText: root.providerError(providerId)

        color: root.palette.surface_container_high
        radius: 13
        implicitHeight: providerColumn.implicitHeight + 20

        ColumnLayout {
            id: providerColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 10
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 9

                IconImage {
                    Layout.preferredWidth: 25
                    Layout.preferredHeight: 25
                    source: root.providerIcon(providerCard.providerId)
                }

                Text {
                    text: providerCard.providerName
                    color: root.palette.on_background
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: providerCard.usageWindows.length > 0
                    text: root.compactPercent(providerCard.providerId)
                    color: root.providerAccent(providerCard.providerId)
                    font.family: root.monoFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            Text {
                Layout.fillWidth: true
                visible: providerCard.errorText.length > 0
                text: providerCard.errorText
                color: root.palette.error
                font.family: root.fontFamily
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            Repeater {
                model: providerCard.usageWindows
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: modelData.label
                            color: root.palette.on_surface_variant
                            font.family: root.fontFamily
                            font.pixelSize: 11
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: `${Math.round(modelData.usedPercent)}% использовано`
                            color: root.palette.on_background
                            font.family: root.monoFamily
                            font.pixelSize: 10
                        }
                    }

                    UsageBar {
                        Layout.fillWidth: true
                        value: modelData.usedPercent
                        accent: root.providerAccent(providerCard.providerId)
                    }

                    Text {
                        text: root.formatReset(modelData.resetsAt)
                        color: root.palette.on_surface_variant
                        font.family: root.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    component CompactProvider: Item {
        id: compactProvider

        required property string providerId
        implicitHeight: 15

        RowLayout {
            anchors.fill: parent
            spacing: 4

            IconImage {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                source: root.providerIcon(compactProvider.providerId)
            }

            UsageBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                value: root.compactValue(compactProvider.providerId)
                accent: root.providerAccent(compactProvider.providerId)
            }

            Text {
                Layout.preferredWidth: 25
                horizontalAlignment: Text.AlignRight
                text: root.compactPercent(compactProvider.providerId)
                color: root.providerAccent(compactProvider.providerId)
                font.family: root.monoFamily
                font.pixelSize: 9
                font.weight: Font.Bold
            }
        }
    }

    component UsageBar: Item {
        id: usageBar
        required property real value
        required property color accent
        implicitHeight: 7

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.palette.outline_variant
            opacity: 0.7
        }

        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            width: parent.width * Math.max(0, Math.min(100, usageBar.value)) / 100
            radius: height / 2
            color: usageBar.value >= 90 ? root.palette.error : usageBar.value >= 75 ? "#f3b562" : usageBar.accent
        }
    }
}
