import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
// One token, one model picker, one harness picker, one Launch. Renders purely from the snapshot
// file the controller writes; nothing here knows a model id, a flag, or a color.
Panel {
  id: root
  moduleName: "sero.hf-agent"
  ipcTarget: "sero.hf-agent"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string sourceDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string cli: sourceDir + "/bin/omarchy-hf-agent"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/hf-agent"

  property var snap: ({ token: {}, models: [], model: "", harnesses: {}, harness: "", error: "" })
  readonly property bool tokenSet: !!(snap.token && snap.token.set)
  readonly property var models: snap.models || []
  readonly property string model: snap.model || ""
  readonly property var harnessList: (snap.harnesses && snap.harnesses.installed) || []
  readonly property string defaultHarness: (snap.harnesses && snap.harnesses.default) || ""
  // the harness the card launches: the pick, else Omarchy's default when installed, else the first
  readonly property string harness: snap.harness || (harnessList.indexOf(defaultHarness) >= 0 ? defaultHarness : (harnessList.length > 0 ? harnessList[0] : ""))
  readonly property bool ready: tokenSet && model !== "" && harness !== ""
  readonly property int shown: 12   // the card lists this many models; the CLI takes any id
  property bool modelsOpen: false
  property bool harnessesOpen: false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Util.alpha(foreground, 0.55)

  function refresh() { if (!poll.running) poll.running = true }
  // every verb finishes when its process exits: no pending state, the snapshot it wrote is the result
  function act(args) { if (action.running) return; action.command = [cli].concat(args); action.running = true }
  function take(json) { try { snap = JSON.parse(json) } catch (e) {} }
  function title() { return model !== "" ? model : "HF Agent" }
  function status() {
    if (snap.error) return snap.error
    if (!tokenSet) return "no token"
    if (model === "") return "no model"
    if (harness === "") return "no installed harness"
    return harness + " · router.huggingface.co"
  }
  // The launch is its own process: the panel closes only when the terminal actually opened, and a
  // refusal (no token, no model) stays on screen instead of vanishing with the panel.
  function launch() {
    if (action.running || agentLaunch.running) return
    agentLaunch.command = [cli, "launch"]; agentLaunch.running = true
  }

  // The controller rewrites the snapshot after every verb; watching the file is what makes the
  // card live. The timer catches a harness installed or removed outside the plugin.
  FileView {
    id: snapshotFile
    path: root.stateDir + "/snapshot.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.take(text())
  }
  Process {
    id: poll
    command: [root.cli, "snapshot"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { if (text.length <= 262144) root.take(text) } }
  }
  Process { id: action; onExited: root.refresh() }
  Process { id: agentLaunch; onExited: function(code) { root.refresh(); if (code === 0) root.close() } }
  Timer { interval: root.opened ? 10000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  onOpenedChanged: if (opened) { refresh(); if (tokenSet && models.length === 0) act(["models"]) }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function launch(): string { root.launch(); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        // The ring is the model's place: hollow until a model is picked, a full dot once it is,
        // urgent ring on an error.
        Rectangle {
          id: ring
          anchors.centerIn: parent; width: Style.space(9); height: width; radius: width / 2
          color: "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: root.snap.error ? (root.bar ? root.bar.urgent : root.foreground) : root.foreground
          opacity: root.model !== "" ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 400 } }
        }
        Rectangle {
          anchors.centerIn: parent
          width: root.model !== "" ? ring.width : 0; height: width; radius: width / 2
          color: root.foreground
          Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        }
      }
    }
    tooltipText: "HF Agent · " + root.title()
    onPressed: function(code) { if (code === Qt.RightButton && root.ready) root.launch(); else root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(220))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onActivateRequested: if (root.ready) root.launch()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)
        Text { width: parent.width; textFormat: Text.PlainText; text: root.title(); color: root.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.heading; font.weight: Font.Medium; elide: Text.ElideRight }
        Text { width: parent.width; textFormat: Text.PlainText; visible: root.status() !== ""; text: root.status(); color: root.snap.error ? (root.bar ? root.bar.urgent : root.foreground) : root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap; maximumLineCount: 3 }
        // The token is typed once, in a terminal, never into the bar: the card only says whether one is set.
        Text { width: parent.width; textFormat: Text.PlainText; text: "Token · " + (root.tokenSet ? "set" : "none"); color: root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
        Text { visible: !root.tokenSet; width: parent.width; textFormat: Text.PlainText; text: "omarchy-hf-agent token <hf_…>"; color: root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WrapAnywhere }
        Link { visible: root.tokenSet; text: "Model · " + (root.model !== "" ? root.model : "none") + (root.modelsOpen ? "  ^" : "  v"); onTriggered: { root.modelsOpen = !root.modelsOpen; if (root.modelsOpen && root.models.length === 0) root.act(["models"]) } }
        Column {
          visible: root.modelsOpen && root.tokenSet; width: parent.width; spacing: Style.space(6)
          Repeater {
            model: root.models.slice(0, root.shown)
            Link { required property var modelData; width: content.width; text: "  " + modelData; opacity: modelData === root.model ? 1 : 0.7; onTriggered: { root.modelsOpen = false; root.act(["model", modelData]) } }
          }
          Text { visible: root.models.length === 0; width: parent.width; textFormat: Text.PlainText; text: "  no models listed yet"; color: root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { width: parent.width; textFormat: Text.PlainText; text: "  more: omarchy-hf-agent model <id>"; color: root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight }
        }
        Link { visible: root.harnessList.length > 0; text: "Harness · " + (root.harness !== "" ? root.harness : "none") + (root.harnessesOpen ? "  ^" : "  v"); onTriggered: root.harnessesOpen = !root.harnessesOpen }
        Text { visible: root.harnessList.length === 0; width: parent.width; textFormat: Text.PlainText; text: "No installed coding agent can be launched"; color: root.dim; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall }
        Column {
          visible: root.harnessesOpen && root.harnessList.length > 0; width: parent.width; spacing: Style.space(6)
          Repeater {
            model: root.harnessList
            Link { required property var modelData; width: content.width; text: "  " + modelData; opacity: modelData === root.harness ? 1 : 0.7; onTriggered: { root.harnessesOpen = false; root.act(["harness", modelData]) } }
          }
        }
        Link { enabled: root.ready && !agentLaunch.running; text: "Launch"; onTriggered: root.launch() }
      }
    }
  }
  component Link: Item {
    signal triggered()
    property alias text: label.text
    property alias enabled: mouse.enabled
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    Rectangle { // rows are the only chrome the panel has; a hover wash says they are buttons
      anchors.fill: parent; radius: Style.space(2)
      color: mouse.containsMouse && mouse.enabled ? Util.alpha(root.foreground, 0.1) : "transparent"
    }
    Text {
      id: label
      width: parent.width; textFormat: Text.PlainText
      color: root.foreground; opacity: mouse.enabled ? 1 : 0.32
      font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: parent.triggered() }
  }
}
