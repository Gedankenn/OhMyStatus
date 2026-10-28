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
  readonly property real panelWidth: Style.space(640)

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
  readonly property var gpus: {
    var list = (snap && snap.gpus) ? snap.gpus : []
    if (list && typeof list.length === "number" && list.length > 0) return list
    return (snap && snap.gpu) ? [snap.gpu] : []
  }
  readonly property var disk: (snap && snap.disk) ? snap.disk : ({})
  readonly property var power: (snap && snap.power) ? snap.power : ({})
  readonly property var bios: (snap && snap.bios) ? snap.bios : ({})
  readonly property string boardName: (snap && snap.board) ? String(snap.board) : ""
  readonly property color statusColor: !reachable ? "#888888" : (stressed ? hot : lime)
  readonly property real powerPct: {
    var cap = Model.num(power.cap_w, 0)
    var w = Model.num(power.watts, 0)
    return cap > 0 ? Math.min(100, (w / cap) * 100) : 0
  }

  property real lastPollMs: 0
  property var cpuHist: []
  property var memHist: []
  property var gpuHist: []
  property var vramHist: []
  property var diskHist: []
  property var pwrHist: []
  property var cpuTempHist: []
  property var memTempHist: []
  property var gpuTempHist: []
  property var vramTempHist: []
  property var diskTempHist: []
  property var diskTempItems: []

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
    if (pollProc.running) return
    if (Date.now() - lastPollMs < 900) return
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
    root.lastPollMs = Date.now()
    var h = parsed.hist || {}
    root.cpuHist = h.cpu || []
    root.memHist = h.mem || []
    root.gpuHist = h.gpu || []
    root.vramHist = h.vram || []
    root.diskHist = h.disk || []
    root.pwrHist = h.pwr || []
    root.cpuTempHist = h.cpu_t || []
    root.memTempHist = h.mem_t || []
    root.gpuTempHist = h.gpu_t || []
    root.vramTempHist = h.vram_t || []
    var dt = h.disk_t || []
    var ids = h.disk_ids || []
    var series = []
    if (dt.length && (typeof dt[0] === "number" || dt[0] === null)) series = [dt]
    else series = dt
    root.diskTempHist = series
    var byId = {}
    for (var s = 0; s < series.length; s++) {
      var sid = (ids && ids.length > s) ? String(ids[s]) : ""
      if (sid) byId[sid] = series[s]
    }
    var drives = (parsed.disk && parsed.disk.drives) ? parsed.disk.drives : []
    var items = []
    var n = (drives && typeof drives.length === "number") ? drives.length : 0
    for (var i = 0; i < n; i++) {
      var dr = drives[i] || {}
      var id = String(dr.id || "")
      items.push({
        label: String(dr.model || id || "disk"),
        id: id,
        temp: dr.temp,
        values: byId[id] || (series.length > i ? series[i] : [])
      })
    }
    if (!items.length && series.length) {
      items.push({
        label: "DISK",
        id: "disk",
        temp: parsed.disk ? parsed.disk.temp : null,
        values: series[0]
      })
    }
    root.diskTempItems = items
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

  component LinePlot: Item {
    id: plotBox
    property var values: []
    property real scaleMax: 100
    property color accent: root.lime
    property string unit: "%"
    property string caption: ""

    readonly property real lastValue: plotBox.lastFinite(plotBox.values)
    readonly property real drawMax: plotBox.ceilingFor(plotBox.values, plotBox.scaleMax, plotBox.unit)
    readonly property int axisW: 34

    function lastFinite(pts) {
      var a = pts || []
      for (var i = a.length - 1; i >= 0; i--) {
        if (a[i] === null || a[i] === undefined || a[i] === "") continue
        var n = Number(a[i])
        if (isFinite(n)) return n
      }
      return 0
    }

    function maxOf(pts) {
      var m = 0
      var a = pts || []
      for (var i = 0; i < a.length; i++) {
        if (a[i] === null || a[i] === undefined || a[i] === "") continue
        var n = Number(a[i])
        if (isFinite(n) && n > m) m = n
      }
      return m
    }

    function ceilingFor(pts, scaleMax, unit) {
      var cap = Math.max(Number(scaleMax) || 0, 1)
      var peak = plotBox.maxOf(pts)
      if (unit === "%") return Math.max(cap, peak)
      if (peak <= cap) return cap
      if (unit === "°") return Math.ceil(peak / 5) * 5
      return Math.ceil(peak)
    }

    function capLabel(n, unit) {
      var v = Number(n)
      if (!isFinite(v)) v = 0
      if (unit === "°") return Math.round(v) + "°"
      if (unit === "W") return Math.round(v) + "W"
      return Math.round(v) + unit
    }

    function peaksFor(pts, cap, w, h) {
      var a = pts || []
      var n = a.length
      if (!n || w < 8 || h < 8) return []
      var xs = []
      var i
      for (i = 0; i < n; i++) {
        var raw = a[i]
        if (raw === null || raw === undefined || raw === "") continue
        var v = Number(raw)
        if (!isFinite(v)) continue
        xs.push({ i: i, v: v })
      }
      if (!xs.length) return []

      var gMax = xs[0]
      var gMin = xs[0]
      for (i = 1; i < xs.length; i++) {
        if (xs[i].v > gMax.v) gMax = xs[i]
        if (xs[i].v < gMin.v) gMin = xs[i]
      }
      if (gMax.v <= 0) return []

      var cands = []
      var span = gMax.v - gMin.v
      if (xs.length === 1 || span < cap * 0.10) {
        var first = -1
        var last = 0
        for (i = 0; i < xs.length; i++) {
          if (xs[i].v < gMax.v) continue
          if (first < 0) first = i
          last = i
        }
        var mid = first < 0 ? Math.floor(xs.length / 2) : Math.floor((first + last) / 2)
        cands.push({ i: xs[mid].i, v: gMax.v })
      } else {
        var riseMin = Math.max(cap * 0.05, span * 0.12)
        for (i = 0; i < xs.length; i++) {
          var prev = i > 0 ? xs[i - 1].v : xs[i].v
          var cur = xs[i].v
          var next = i + 1 < xs.length ? xs[i + 1].v : xs[i].v
          if (cur > prev && cur >= next && (cur - prev) >= riseMin)
            cands.push(xs[i])
        }
        var hasMax = false
        for (i = 0; i < cands.length; i++) {
          if (cands[i].i === gMax.i) { hasMax = true; break }
        }
        if (!hasMax) cands.push(gMax)
      }

      cands.sort(function (a, b) { return b.v - a.v })

      var out = []
      var minDx = Math.max(40, w * 0.18)
      for (i = 0; i < cands.length && out.length < 4; i++) {
        var p = cands[i]
        var x = n === 1 ? w * 0.5 : p.i * (w - 1) / (n - 1)
        var clash = false
        for (var k = 0; k < out.length; k++) {
          if (Math.abs(x - out[k].x) < minDx) { clash = true; break }
        }
        if (clash) continue
        var y = h - 1 - (h - 2) * Math.max(0, Math.min(1, p.v / cap))
        out.push({ x: x, y: y, v: p.v })
      }
      return out
    }

    Rectangle {
      anchors.fill: parent
      radius: 3
      color: Qt.rgba(plotBox.accent.r, plotBox.accent.g, plotBox.accent.b, 0.12)
    }

    AxisRail {
      id: leftRail
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: 2
      width: plotBox.axisW
      accent: plotBox.accent
      ratio: Math.max(0, Math.min(1, plotBox.lastValue / Math.max(plotBox.drawMax, 1)))
      topText: String(Math.round(Math.max(plotBox.drawMax, 0)))
      botText: plotBox.capLabel(0, plotBox.unit)
      railOnLeft: true
    }

    Canvas {
      id: plot
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: leftRail.right
      anchors.right: parent.right
      anchors.leftMargin: 3
      anchors.rightMargin: 4
      anchors.topMargin: 3
      anchors.bottomMargin: 3

      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onVisibleChanged: if (visible) requestPaint()

      Connections {
        target: plotBox
        function onValuesChanged() { plot.requestPaint() }
        function onScaleMaxChanged() { plot.requestPaint() }
        function onDrawMaxChanged() { plot.requestPaint() }
        function onAccentChanged() { plot.requestPaint() }
      }

      onPaint: {
        var ctx = getContext("2d")
        var w = width
        var h = height
        ctx.clearRect(0, 0, w, h)
        if (w < 2 || h < 2) return

        var va = plotBox.accent
        var stroke = "rgb(" + Math.round(va.r * 255) + ", " + Math.round(va.g * 255) + ", " + Math.round(va.b * 255) + ")"
        var cap = Math.max(plotBox.drawMax, 1)
        var pts = plotBox.values || []
        var n = pts.length
        if (!n) return

        ctx.strokeStyle = stroke
        ctx.lineWidth = 1.9
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()
        var started = false
        for (var i = 0; i < n; i++) {
          var raw = pts[i]
          if (raw === null || raw === undefined || raw === "") { started = false; continue }
          var v = Number(raw)
          if (!isFinite(v)) { started = false; continue }
          var x = n === 1 ? w * 0.5 : i * (w - 1) / (n - 1)
          var y = h - 1 - (h - 2) * Math.max(0, Math.min(1, v / cap))
          if (!started) { ctx.moveTo(x, y); started = true }
          else ctx.lineTo(x, y)
        }
        ctx.stroke()

        var peaks = plotBox.peaksFor(pts, cap, w, h)
        if (!peaks.length) return

        var fam = String(root.contentFontFamily || "sans-serif").replace(/"/g, "")
        ctx.font = "700 9px \"" + fam + "\""
        ctx.textBaseline = "alphabetic"
        ctx.textAlign = "left"

        var pi
        for (pi = 0; pi < peaks.length; pi++) {
          var pk = peaks[pi]
          ctx.beginPath()
          ctx.fillStyle = stroke
          ctx.arc(pk.x, pk.y, 2.1, 0, Math.PI * 2)
          ctx.fill()
        }

        for (pi = 0; pi < peaks.length; pi++) {
          pk = peaks[pi]
          var label = plotBox.capLabel(pk.v, plotBox.unit)
          var tw = ctx.measureText(label).width
          var lx = pk.x - tw / 2
          if (lx < 1) lx = 1
          if (lx + tw > w - 1) lx = Math.max(1, w - 1 - tw)
          var ly = pk.y - 6
          if (ly < 10) ly = pk.y + 12
          if (plotBox.caption.length > 0 && pk.x > w * 0.62 && pk.y < 18 && ly < 12)
            ly = pk.y + 12

          var padX = 2.5
          var padY = 2
          ctx.fillStyle = "rgba(8, 10, 8, 0.72)"
          ctx.fillRect(lx - padX, ly - 8 - padY, tw + padX * 2, 10 + padY * 2)
          ctx.fillStyle = stroke
          ctx.fillText(label, lx, ly)
        }
      }
    }

    Text {
      visible: plotBox.caption.length > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: 4
      anchors.rightMargin: 6
      text: plotBox.caption
      color: Qt.rgba(plotBox.accent.r, plotBox.accent.g, plotBox.accent.b, 0.7)
      font.family: root.contentFontFamily
      font.pixelSize: 9
      font.letterSpacing: 0.8
      font.weight: Font.DemiBold
    }
  }

  component DiskTempStack: Item {
    id: stack
    property var items: []

    readonly property int count: (stack.items && typeof stack.items.length === "number") ? stack.items.length : 0

    Repeater {
      model: stack.count
      delegate: Item {
        required property int index
        readonly property var item: stack.items[index] || ({})
        width: stack.width
        height: stack.count > 0 ? Math.floor((stack.height - Style.space(4) * (stack.count - 1)) / stack.count) : stack.height
        y: index * (height + Style.space(4))

        LinePlot {
          anchors.left: parent.left
          anchors.right: nowLabel.left
          anchors.rightMargin: Style.space(6)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          values: parent.item.values || []
          scaleMax: 110
          accent: root.tempColor(parent.item.temp)
          unit: "°"
          caption: String(parent.item.label || "")
        }
        Text {
          id: nowLabel
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 40
          textFormat: Text.PlainText
          text: Model.deg(parent.item.temp)
          color: root.tempColor(parent.item.temp)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.Bold
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }

  component AxisRail: Item {
    id: rail
    property color accent: root.lime
    property real ratio: 0
    property string topText: ""
    property string botText: ""
    property bool railOnLeft: true

    Rectangle {
      id: track
      width: 3
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: rail.railOnLeft ? parent.left : undefined
      anchors.right: rail.railOnLeft ? undefined : parent.right
      radius: width / 2
      color: Qt.rgba(rail.accent.r, rail.accent.g, rail.accent.b, 0.22)

      Rectangle {
        width: parent.width
        height: Math.max(parent.width, parent.height * Math.max(0, Math.min(1, rail.ratio)))
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        radius: width / 2
        color: rail.accent
      }
    }

    Text {
      anchors.top: parent.top
      anchors.left: rail.railOnLeft ? track.right : parent.left
      anchors.right: rail.railOnLeft ? parent.right : track.left
      anchors.leftMargin: rail.railOnLeft ? 3 : 0
      anchors.rightMargin: rail.railOnLeft ? 0 : 3
      text: rail.topText
      color: rail.accent
      font.family: root.contentFontFamily
      font.pixelSize: 9
      font.weight: Font.DemiBold
      horizontalAlignment: rail.railOnLeft ? Text.AlignLeft : Text.AlignRight
      wrapMode: Text.NoWrap
    }
    Text {
      anchors.bottom: parent.bottom
      anchors.left: rail.railOnLeft ? track.right : parent.left
      anchors.right: rail.railOnLeft ? parent.right : track.left
      anchors.leftMargin: rail.railOnLeft ? 3 : 0
      anchors.rightMargin: rail.railOnLeft ? 0 : 3
      text: rail.botText
      color: Qt.rgba(rail.accent.r, rail.accent.g, rail.accent.b, 0.7)
      font.family: root.contentFontFamily
      font.pixelSize: 9
      horizontalAlignment: rail.railOnLeft ? Text.AlignLeft : Text.AlignRight
      elide: Text.ElideRight
    }
  }

  component HistRow: Item {
    id: hrow
    property string name: ""
    property string subname: ""
    property string value: ""
    property string extra: ""
    property color accent: root.lime
    property color extraColor: root.lime
    property var values: []
    property var temps: []
    property var diskTemps: []
    property real scaleMax: 100
    property real tempScaleMax: 110
    property color tempAccent: root.hot
    property string valueUnit: "%"
    property real chartH: Style.space(56)

    readonly property bool showDiskTemps: {
      var items = hrow.diskTemps || []
      return !!(items && typeof items.length === "number" && items.length > 0)
    }
    readonly property bool showTemp: {
      if (hrow.showDiskTemps) return true
      var pts = hrow.temps || []
      for (var i = 0; i < pts.length; i++) {
        var raw = pts[i]
        if (raw === null || raw === undefined || raw === "") continue
        if (isFinite(Number(raw))) return true
      }
      return false
    }

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
          id: hSub
          anchors.left: hName.right
          anchors.leftMargin: Style.space(8)
          anchors.right: hValue.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: hrow.subname
          visible: text.length > 0
          elide: Text.ElideRight
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
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
        width: parent.width
        height: hrow.chartH

        LinePlot {
          id: usagePlot
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: hrow.showTemp ? Math.floor((parent.width - Style.space(8)) / 2) : parent.width
          values: hrow.values
          scaleMax: hrow.scaleMax
          accent: hrow.accent
          unit: hrow.valueUnit
        }
        LinePlot {
          id: tempPlot
          visible: hrow.showTemp && !hrow.showDiskTemps
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: (hrow.showTemp && !hrow.showDiskTemps) ? Math.floor((parent.width - Style.space(8)) / 2) : 0
          values: hrow.temps
          scaleMax: hrow.tempScaleMax
          accent: hrow.tempAccent
          unit: "°"
          caption: "TEMP"
        }
        DiskTempStack {
          visible: hrow.showDiskTemps
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: hrow.showDiskTemps ? Math.floor((parent.width - Style.space(8)) / 2) : 0
          items: hrow.diskTemps
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
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

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
              subname: root.cpu.name || ""
              value: Model.pct(root.cpu.percent)
              extra: Model.tempWatts(root.cpu.temp, root.power.cpu_w, root.power.cpu_source !== "rapl")
              values: root.cpuHist
              temps: root.cpuTempHist
              scaleMax: 100
              accent: root.heatColor(root.cpu.percent, root.cpuCool)
              extraColor: root.tempColor(root.cpu.temp)
              tempAccent: root.tempColor(root.cpu.temp)
            }
            HistRow {
              name: "RAM"
              subname: Model.ramKind(root.mem)
              value: Model.pct(root.mem.percent)
              extra: Model.ramExtra(root.mem)
              values: root.memHist
              temps: root.memTempHist
              scaleMax: 100
              accent: root.heatColor(root.mem.percent, root.ramCool)
              extraColor: root.tempColor(root.mem.temp)
              tempAccent: root.tempColor(root.mem.temp)
            }
            Repeater {
              model: root.gpus.length

              delegate: Column {
                id: gpuBlock
                required property int index
                width: contentColumn.width
                spacing: Style.space(9)

                readonly property var card: root.gpus[index] || ({})

                HistRow {
                  name: gpuBlock.index === 0 ? "GPU" : "GPU " + (gpuBlock.index + 1)
                  subname: String(gpuBlock.card.name || "")
                  value: Model.pct(gpuBlock.card.percent)
                  extra: Model.tempWatts(gpuBlock.card.temp, gpuBlock.card.power_w, false)
                  values: root.gpuHist.length > gpuBlock.index ? root.gpuHist[gpuBlock.index] : []
                  temps: root.gpuTempHist.length > gpuBlock.index ? root.gpuTempHist[gpuBlock.index] : []
                  scaleMax: 100
                  accent: root.heatColor(gpuBlock.card.percent, root.gpuCool)
                  extraColor: root.tempColor(gpuBlock.card.temp)
                  tempAccent: root.tempColor(gpuBlock.card.temp)
                }
                HistRow {
                  name: "VRAM"
                  value: Model.pct(gpuBlock.card.vram_percent)
                  extra: {
                    var base = (gpuBlock.card.vram_used_mb || 0) + "/" + (gpuBlock.card.vram_total_mb || 0) + " M"
                    var t = Model.deg(gpuBlock.card.temp_mem)
                    return t === "—" ? base : base + " · " + t
                  }
                  values: root.vramHist.length > gpuBlock.index ? root.vramHist[gpuBlock.index] : []
                  temps: root.vramTempHist.length > gpuBlock.index ? root.vramTempHist[gpuBlock.index] : []
                  scaleMax: 100
                  accent: root.heatColor(gpuBlock.card.vram_percent, root.vramCool)
                  extraColor: gpuBlock.card.temp_mem !== undefined && gpuBlock.card.temp_mem !== null && gpuBlock.card.temp_mem !== ""
                    ? root.tempColor(gpuBlock.card.temp_mem)
                    : root.heatColor(gpuBlock.card.vram_percent, root.vramCool)
                  tempAccent: root.tempColor(gpuBlock.card.temp_mem)
                }
              }
            }
            HistRow {
              name: "DISK"
              value: Model.pct(root.disk.percent)
              extra: Model.diskExtra(root.disk)
              values: root.diskHist
              diskTemps: root.diskTempItems
              scaleMax: 100
              accent: root.heatColor(root.disk.percent, root.diskCool)
              extraColor: root.tempColor(root.disk.temp)
              tempAccent: root.tempColor(root.disk.temp)
              chartH: Style.space(Math.max(56, 40 * Math.max(1, root.diskTempItems.length)))
            }
            HistRow {
              visible: root.power.watts !== undefined && root.power.watts !== null && root.power.watts !== ""
              name: "POWER"
              value: Model.watts(root.power.watts)
              extra: ""
              values: root.pwrHist
              scaleMax: Math.max(Model.num(root.power.cap_w, 0), 1)
              accent: root.heatColor(root.powerPct, root.powerCool)
              extraColor: root.powerCool
              valueUnit: "W"
            }
          }

          Column {
            visible: root.reachable
            width: parent.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              visible: text.length > 0
              text: root.boardName
              color: Qt.rgba(root.lime.r, root.lime.g, root.lime.b, 0.55)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              visible: text.length > 0
              text: Model.biosLine(root.bios)
              color: Qt.rgba(root.lime.r, root.lime.g, root.lime.b, 0.45)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              visible: text.length > 0
              text: Model.sysLine(root.snap)
              color: Qt.rgba(root.lime.r, root.lime.g, root.lime.b, 0.45)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              visible: text.length > 0
              text: Model.hwLine(root.cpu, root.mem)
              color: Qt.rgba(root.lime.r, root.lime.g, root.lime.b, 0.45)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
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
