import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "ohmystatus"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = chip
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: chip.width
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property var cpu: panelLoader.item ? panelLoader.item.cpu : ({})
  readonly property var mem: panelLoader.item ? panelLoader.item.mem : ({})
  readonly property var gpu: panelLoader.item ? panelLoader.item.gpu : ({})
  readonly property var disk: panelLoader.item ? panelLoader.item.disk : ({})
  readonly property string tooltip: panelLoader.item ? panelLoader.item.tooltipText : "host"

  readonly property string displayFont: bar ? bar.fontFamily : Style.font.family
  readonly property string bodyFont: bar ? bar.fontFamily : Style.font.family

  function fmt(v) { return Math.round(Math.min(Number(v) || 0, 99)) + "%" }
  function deg(v) { return Math.round(Number(v) || 0) + "°" }

  function meterColor(pct) {
    var n = (Number(pct) || 0) / 100
    if (n >= 0.85) return "#C41E3A"
    if (n >= 0.6) return "#FF6A00"
    return "#A8FF3E"
  }

  function tempColor(value) {
    if (value >= 85) return "#C41E3A"
    if (value >= 75) return "#FF6A00"
    return "#e8dcc8"
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: chip.implicitWidth
  implicitHeight: Math.max(30, chip.implicitHeight)

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  component MeterCell: Item {
    required property string name
    required property string value
    required property color valueColor
    property int cellWidth: 60
    property int valueWidth: 32
    width: cellWidth
    height: cellText.implicitHeight

    Text {
      id: nameText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.name
      color: "#9A8B7C"
      font.family: root.displayFont
      font.pixelSize: 12
      font.weight: 500
      font.letterSpacing: 1
      font.capitalization: Font.AllUppercase
    }
    Text {
      id: cellText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.value
      color: parent.valueColor
      font.family: root.bodyFont
      font.pixelSize: 14
      font.weight: Font.Bold
      font.letterSpacing: 0.5
      width: parent.valueWidth
      horizontalAlignment: Text.AlignRight
    }
  }

  Item {
    id: chip
    anchors.centerIn: parent
    implicitWidth: row.implicitWidth + 16
    implicitHeight: row.implicitHeight + 4
    height: implicitHeight
    width: implicitWidth

    Row {
      id: row
      spacing: 6
      anchors.centerIn: parent

      MeterCell { name: "CPU";  value: root.fmt(root.cpu.percent);  valueColor: root.meterColor(root.cpu.percent) }
      MeterCell { name: "TMP";  value: root.deg(root.cpu.temp);     valueColor: root.tempColor(root.cpu.temp) }
      MeterCell { name: "MEM";  value: root.fmt(root.mem.percent);  valueColor: root.meterColor(root.mem.percent) }
      MeterCell { name: "GPU";  value: root.fmt(root.gpu.percent);  valueColor: root.meterColor(root.gpu.percent) }
      MeterCell { name: "GTMP"; value: root.deg(root.gpu.temp);     valueColor: root.tempColor(root.gpu.temp) }
      MeterCell { name: "VRAM"; value: root.fmt(root.gpu.vram_percent); valueColor: root.meterColor(root.gpu.vram_percent); cellWidth: 72; valueWidth: 42 }
      MeterCell { name: "DISK"; value: root.fmt(root.disk.percent); valueColor: root.meterColor(root.disk.percent) }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, Model.asPlainUi(root.tooltip, 240))
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
