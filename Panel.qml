import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ohmystatus"
  ipcTarget: "ohmystatus"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property int refreshSeconds: Math.max(3, parseInt(setting("refreshSeconds", 5), 10) || 5)
  readonly property string pluginDir: {
    var s = String(Qt.resolvedUrl("./poll.py"))
    s = s.replace(/^file:\/\//, "")
    return s.replace(/\/poll\.py$/, "")
  }
  readonly property string pollPy: pluginDir + "/poll.py"
  readonly property string pythonBin: "/usr/bin/python3"
  readonly property real panelWidth: Style.space(360)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color lime: "#8FDB4F"
  readonly property color cpuCool: "#8FDB4F"
  readonly property color ramCool: "#4EC4E8"
  readonly property color gpuCool: "#C084FC"
  readonly property color vramCool: "#FFB020"
  readonly property color diskCool: "#3DDC97"
  readonly property color powerCool: "#FF7A45"
  readonly property color hot: "#E23B3B"
  readonly property color warm: "#FFB020"

  property var snap: null
  property int pollRetries: 0

  readonly property string label: Model.barLabel(snap)
  readonly property string tooltipText: Model.tooltip(snap)
  readonly property bool fetching: pollProc.running
  readonly property bool reachable: !!(snap && snap.reachable)
  readonly property bool stressed: Model.stressed(snap, 80)
  readonly property var cpu: (snap && snap.cpu) ? snap.cpu : ({})
  readonly property var mem: (snap && snap.mem) ? snap.mem : ({})
  readonly property var gpu: (snap && snap.gpu) ? snap.gpu : ({})
  readonly property var disk: (snap && snap.disk) ? snap.disk : ({})
  readonly property var power: (snap && snap.power) ? snap.power : ({})
  readonly property color statusColor: !reachable ? "#888888" : (stressed ? hot : lime)
  readonly property real powerPct: {
    var cap = Model.num(power.cap_w, 0)
    var w = Model.num(power.watts, 0)
    return cap > 0 ? Math.min(100, (w / cap) * 100) : 0
  }

  ListModel { id: cpuHist }
  ListModel { id: memHist }
  ListModel { id: gpuHist }
  ListModel { id: vramHist }
  ListModel { id: diskHist }
  ListModel { id: pwrHist }

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (!root.bar) return
    if (typeof root.bar.setCenterHoverRevealSuppressed === "function") {
      root.bar.setCenterHoverRevealSuppressed(value)
      return
    }
    if ("centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    pollRetries = 0
    startPoll()
  }

  function startPoll() {
    restartProc(pollProc, [root.pythonBin, root.pollPy])
  }

  function restartProc(proc, command) {
    proc.command = command
    if (proc.running) {
      proc.running = false
      Qt.callLater(function() { proc.running = true })
      return
    }
    proc.running = true
  }

  function applySnap(text) {
    var parsed = Model.parseSnap(text)
    if (!parsed) {
      if (pollRetries < 3) {
        pollRetries++
        pollRetryTimer.restart()
      }
      return
    }
    root.snap = parsed
    root.pollRetries = 0
    root.fillHist(cpuHist, parsed.hist ? parsed.hist.cpu : null)
    root.fillHist(memHist, parsed.hist ? parsed.hist.mem : null)
    root.fillHist(gpuHist, parsed.hist ? parsed.hist.gpu : null)
    root.fillHist(vramHist, parsed.hist ? parsed.hist.vram : null)
    root.fillHist(diskHist, parsed.hist ? parsed.hist.disk : null)
    root.fillHist(pwrHist, parsed.hist ? parsed.hist.pwr : null)
  }

  function fillHist(model, arr) {
    model.clear()
    var pts = Model.histPoints(arr)
    for (var i = 0; i < pts.length; i++) model.append(pts[i])
  }

  function heatColor(pct, cool) {
    var n = Number(pct)
    if (!isFinite(n)) n = 0
    if (n >= 80) return hot
    if (n >= 55) return warm
    return cool
  }

  function tempColor(v) {
    var n = Number(v)
    if (!isFinite(n)) return Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.45)
    if (n >= 80) return hot
    if (n >= 65) return warm
    return lime
  }

  Process {
    id: pollProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySnap(text)
    }
  }

  Timer {
    id: pollRetryTimer
    interval: 1800
    onTriggered: root.startPoll()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  component MeterRow: Item {
    id: row
    property string name: ""
    property string value: ""
    property string extra: ""
    property real ratio: 0
    property color accent: root.lime
    property color extraColor: root.lime

    property real shownRatio: 0

    width: parent ? parent.width : 0
    height: col.implicitHeight

    onRatioChanged: shownRatio = Math.max(0, Math.min(1, ratio))
    Component.onCompleted: shownRatio = Math.max(0, Math.min(1, ratio))

    Behavior on shownRatio {
      NumberAnimation { duration: 520; easing.type: Easing.OutCubic }
    }

    Column {
      id: col
      width: row.width
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: Math.max(nameLabel.implicitHeight, valueLabel.implicitHeight)

        Text {
          id: nameLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.name
          color: row.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1.2
          font.weight: Font.DemiBold
          opacity: 0.9
        }
        Text {
          id: extraLabel
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.extra
          color: row.extraColor
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          visible: row.extra.length > 0
        }
        Text {
          id: valueLabel
          anchors.right: extraLabel.visible ? extraLabel.left : parent.right
          anchors.rightMargin: extraLabel.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.value
          color: row.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.Bold
        }
      }

      Rectangle {
        id: track
        width: parent.width
        height: Style.space(8)
        radius: height / 2
        color: Qt.rgba(row.accent.r, row.accent.g, row.accent.b, 0.14)

        Rectangle {
          id: fill
          width: Math.max(track.height, (track.width) * row.shownRatio)
          height: track.height
          radius: height / 2
          clip: true

          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.darker(row.accent, 1.25) }
            GradientStop { position: 0.55; color: row.accent }
            GradientStop { position: 1.0; color: Qt.lighter(row.accent, 1.25) }
          }

          Rectangle {
            id: shine
            width: Math.max(18, fill.width * 0.28)
            height: fill.height
            radius: fill.radius
            opacity: 0.35
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: "transparent" }
              GradientStop { position: 0.5; color: "#ffffff" }
              GradientStop { position: 1.0; color: "transparent" }
            }

            SequentialAnimation on x {
              running: root.opened && row.shownRatio > 0.04
              loops: Animation.Infinite
              NumberAnimation {
                from: -shine.width
                to: Math.max(fill.width, 40)
                duration: 1600
                easing.type: Easing.InOutQuad
              }
              PauseAnimation { duration: 700 }
            }
          }
        }
      }
    }
  }

  component HistRow: Item {
    id: hrow
    property string name: ""
    property string value: ""
    property string extra: ""
    property color accent: root.lime
    property color extraColor: root.lime
    property var points
    property real scaleMax: 100
    property real chartH: Style.space(44)

    width: parent ? parent.width : 0
    height: hcol.implicitHeight

    Column {
      id: hcol
      width: hrow.width
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: Math.max(hName.implicitHeight, hValue.implicitHeight)

        Text {
          id: hName
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: hrow.name
          color: hrow.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1.2
          font.weight: Font.DemiBold
          opacity: 0.9
        }
        Text {
          id: hExtra
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: hrow.extra
          color: hrow.extraColor
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          visible: hrow.extra.length > 0
        }
        Text {
          id: hValue
          anchors.right: hExtra.visible ? hExtra.left : parent.right
          anchors.rightMargin: hExtra.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: hrow.value
          color: hrow.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.Bold
        }
      }

      Item {
        id: chart
        width: parent.width
        height: hrow.chartH

        Rectangle {
          anchors.fill: parent
          radius: 3
          color: Qt.rgba(hrow.accent.r, hrow.accent.g, hrow.accent.b, 0.14)
        }

        Canvas {
          id: plot
          anchors.fill: parent
          anchors.margins: 2

          function paintLine() { requestPaint() }

          onWidthChanged: paintLine()
          onHeightChanged: paintLine()
          onVisibleChanged: if (visible) paintLine()

          Connections {
            target: hrow.points
            function onCountChanged() { plot.paintLine() }
            function onDataChanged() { plot.paintLine() }
          }

          Connections {
            target: hrow
            function onScaleMaxChanged() { plot.paintLine() }
            function onAccentChanged() { plot.paintLine() }
          }

          onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            ctx.clearRect(0, 0, w, h)
            var pts = hrow.points
            if (!pts || pts.count < 1 || w < 2 || h < 2) return
            var n = pts.count
            var cap = Math.max(hrow.scaleMax, 1)
            var c = hrow.accent
            var stroke = "rgb(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ")"
            ctx.strokeStyle = stroke
            ctx.fillStyle = "rgba(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ", 0.18)"
            ctx.lineWidth = 1.8
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.beginPath()
            for (var i = 0; i < n; i++) {
              var v = Number(pts.get(i).v)
              if (!isFinite(v)) v = 0
              var x = n === 1 ? w * 0.5 : i * (w - 1) / (n - 1)
              var y = h - 1 - (h - 2) * Math.max(0, Math.min(1, v / cap))
              if (i === 0) ctx.moveTo(x, y)
              else ctx.lineTo(x, y)
            }
            ctx.stroke()
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    padding: Style.spacing.md
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: popupScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(10)

          Row {
            spacing: Style.space(8)

            Image {
              id: headerMark
              width: Style.space(18)
              height: Style.space(18)
              fillMode: Image.PreserveAspectFit
              source: Qt.resolvedUrl("assets/omarchy.png")
              sourceSize.width: 64
              sourceSize.height: 64
              anchors.verticalCenter: parent.verticalCenter
              opacity: root.reachable ? 1 : 0.35

              SequentialAnimation on scale {
                running: root.opened && root.reachable && !root.stressed
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.08; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1.08; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.reachable && root.snap && root.snap.host
                ? String(root.snap.host).toUpperCase()
                : "HOST"
              color: root.statusColor
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.letterSpacing: 1.4
              font.weight: Font.DemiBold
              elide: Text.ElideRight

              Behavior on color { ColorAnimation { duration: 220 } }
            }
          }

          Column {
            visible: root.reachable
            width: contentColumn.width
            spacing: Style.space(9)

            HistRow {
              name: "CPU"
              value: Model.pct(root.cpu.percent)
              extra: Model.tempWatts(root.cpu.temp, root.power.cpu_w, root.power.cpu_source !== "rapl")
              points: cpuHist
              scaleMax: 100
              accent: root.heatColor(root.cpu.percent, root.cpuCool)
              extraColor: root.tempColor(root.cpu.temp)
            }
            HistRow {
              name: "RAM"
              value: Model.pct(root.mem.percent)
              extra: (root.mem.used_gb || 0) + "/" + (root.mem.total_gb || 0) + " G"
              points: memHist
              scaleMax: 100
              accent: root.heatColor(root.mem.percent, root.ramCool)
              extraColor: root.heatColor(root.mem.percent, root.ramCool)
            }
            HistRow {
              name: "GPU"
              value: Model.pct(root.gpu.percent)
              extra: Model.tempWatts(root.gpu.temp, root.power.gpu_w, false)
              points: gpuHist
              scaleMax: 100
              accent: root.heatColor(root.gpu.percent, root.gpuCool)
              extraColor: root.tempColor(root.gpu.temp)
            }
            HistRow {
              name: "VRAM"
              value: Model.pct(root.gpu.vram_percent)
              extra: (root.gpu.vram_used_mb || 0) + "/" + (root.gpu.vram_total_mb || 0) + " M"
              points: vramHist
              scaleMax: 100
              accent: root.heatColor(root.gpu.vram_percent, root.vramCool)
              extraColor: root.heatColor(root.gpu.vram_percent, root.vramCool)
            }
            HistRow {
              name: "DISK"
              value: Model.pct(root.disk.percent)
              extra: Model.diskExtra(root.disk)
              points: diskHist
              scaleMax: 100
              accent: root.heatColor(root.disk.percent, root.diskCool)
              extraColor: root.heatColor(root.disk.percent, root.diskCool)
            }
            HistRow {
              visible: root.power.watts !== undefined && root.power.watts !== null && root.power.watts !== ""
              name: "POWER"
              value: Model.watts(root.power.watts)
              extra: ""
              points: pwrHist
              scaleMax: Math.max(Model.num(root.power.cap_w, 0), 1)
              accent: root.heatColor(root.powerPct, root.powerCool)
              extraColor: root.powerCool
              chartH: Style.space(56)
            }
          }

          Text {
            visible: root.reachable
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: {
              var bits = []
              if (root.cpu.name) bits.push(root.cpu.name)
              if (root.cpu.cores) bits.push(root.cpu.cores + " th")
              if (root.gpu.name) bits.push(root.gpu.name)
              return bits.join("   ·   ")
            }
            color: Qt.rgba(root.lime.r, root.lime.g, root.lime.b, 0.55)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: !root.reachable
            width: parent.width
            text: root.fetching ? "Lendo o host…" : (root.snap && root.snap.error ? String(root.snap.error) : "host offline")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.fetching ? root.warm : root.hot
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }
        }
      }
    }
  }
}
