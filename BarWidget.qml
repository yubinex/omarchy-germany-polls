import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Polls.js" as Polls

// Shows one parliament's polls (the Bundestag by default) as the leading
// party, a ticker of every party, or just an icon, and owns the DAWUM fetch;
// the panel only presents what this widget parsed.
BarWidget {
  id: root
  moduleName: "yubinex.germany-polls"

  // DAWUM parliament id shown in the bar: "0" is the Bundestag, 1-16 the states.
  readonly property string barParliament: String(setting("parliament", "0"))
  // "leader" shows the leading party, "ticker" scrolls through every party,
  // "icon" shows only a ballot box so no results appear in the bar at all,
  // and "hidden" removes the widget. `screenDisplay` overrides `barDisplay`
  // per monitor, e.g. { "DP-1": "ticker" }.
  readonly property string screenName: barWindow && barWindow.screen ? String(barWindow.screen.name || "") : ""
  readonly property string barDisplay: {
    var perScreen = setting("screenDisplay", {})
    var mode = perScreen && screenName && perScreen[screenName] ? perScreen[screenName] : setting("barDisplay", "leader")
    return mode === "ticker" || mode === "icon" || mode === "hidden" ? mode : "leader"
  }
  readonly property bool iconMode: barDisplay === "icon"
  // Visible width of the ticker, in unscaled pixels.
  readonly property int tickerWidth: Number(setting("tickerWidth", 220)) || 220
  property var polls: null
  property double fetchedMs: 0
  property bool fetchFailed: false

  readonly property var summary: polls ? polls.parliaments[barParliament] || null : null
  readonly property var leader: summary ? summary.leader : null
  readonly property bool tickerMode: barDisplay === "ticker" && !vertical && leader !== null
  readonly property var tickerParties: summary ? summary.results.filter(function(r) { return !r.other }) : []
  readonly property string label: {
    if (iconMode) return "\u{F0A20}"
    if (!leader) return fetchFailed ? "Polls —" : "Polls …"
    // A vertical bar has no room to scroll; stay neutral rather than fall
    // back to naming the leader.
    if (barDisplay === "ticker") return "Polls"
    if (vertical) return leader.party
    return leader.party + " " + Polls.formatPercent(leader.percent)
  }
  readonly property string tooltip: {
    // Icon mode exists to keep results off the bar; hovering must not reveal them.
    if (iconMode) return "Germany Polls"
    if (!summary) return fetchFailed ? "Could not reach DAWUM" : "Loading polls…"
    var lines = [summary.shortcut]
    var results = summary.results.slice(0, 6)
    for (var i = 0; i < results.length; ++i)
      lines.push(results[i].party + "  " + Polls.formatPercent(results[i].percent))
    lines.push(Polls.sourceLine(summary))
    return lines.join("\n")
  }

  function refresh() {
    if (!fetchProcess.running) fetchProcess.running = true
  }

  // The bar collapses a slot whose widget is invisible.
  visible: barDisplay !== "hidden"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The shell's `summon`/`hide`/`toggle` routes (e.g. a keybind running
  // `omarchy-shell shell toggle yubinex.germany-polls`) call these.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // The panel centres itself on its anchor. Anchoring it to the button would
  // make it slide whenever the button resizes while open (e.g. switching
  // leader/ticker from the panel), so it anchors to a zero-size point that
  // stays fixed on screen until the panel closes.
  readonly property var barWindow: root.QsWindow.window
  TransformWatcher {
    id: positionWatcher
    a: root.barWindow ? root.barWindow.contentItem : null
    b: root
  }
  readonly property point windowPos: {
    positionWatcher.transform  // reactive dependency
    return barWindow ? root.mapToItem(barWindow.contentItem, 0, 0) : Qt.point(0, 0)
  }
  property bool anchorPinned: false
  property point pinnedCenter: Qt.point(0, 0)
  onOpenedChanged: {
    if (opened) pinnedCenter = Qt.point(windowPos.x + width / 2, windowPos.y + height / 2)
    anchorPinned = opened
  }

  Item {
    id: panelAnchor
    width: 0
    height: 0
    x: root.anchorPinned ? root.pinnedCenter.x - root.windowPos.x : root.width / 2
    y: root.anchorPinned ? root.pinnedCenter.y - root.windowPos.y : root.height / 2
  }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.polls = polls
    panelLoader.item.fetchedMs = fetchedMs
    panelLoader.item.fetchFailed = fetchFailed
    panelLoader.item.settings = settings
    panelLoader.item.hostWidget = root
    panelLoader.item.hostScreen = screenName
    panelLoader.item.anchorItem = panelAnchor
    panelLoader.item.bar = bar
  }

  onPollsChanged: injectPanel()
  onFetchedMsChanged: injectPanel()
  onFetchFailedChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onBarChanged: injectPanel()
  onScreenNameChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }

  // DAWUM publishes a few times a day; half-hourly keeps the map current
  // without hammering a volunteer-run API.
  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProcess
    command: ["curl", "-fsSL", "--proto", "=https", "--proto-redir", "=https", "--max-redirs", "3", "--connect-timeout", "8", "--max-time", "20", "--max-filesize", "2097152", "https://api.dawum.de/newest_surveys.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function() {
        var parsed = Polls.parse(text)
        if (parsed) {
          root.polls = parsed
          root.fetchedMs = Date.now()
          root.fetchFailed = false
        } else {
          // Keep showing the last good data; only flag the failure.
          root.fetchFailed = true
        }
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    hasVisualContent: true
    fixedWidth: (root.tickerMode ? ticker.width : content.implicitWidth) + Style.space(20)
    tooltipText: root.tooltip
    horizontalMargin: 8.75

    Row {
      id: content
      visible: !root.tickerMode
      anchors.centerIn: parent
      spacing: Style.space(6)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.barDisplay === "leader"
        width: Style.space(9)
        height: width
        radius: width / 2
        color: root.leader ? root.leader.color : "transparent"
        border.width: root.leader ? 0 : 1
        border.color: button.foreground
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: root.iconMode ? Style.bar.iconFont : Style.font.bodySmall
        font.bold: !root.iconMode
      }
    }

    Item {
      id: ticker
      visible: root.tickerMode
      anchors.centerIn: parent
      width: Style.space(root.tickerWidth)
      height: parent.height
      clip: true

      // Two identical copies side by side; scrolling exactly one copy's width
      // and jumping back makes the loop seamless.
      Row {
        id: tickerStrip
        anchors.verticalCenter: parent.verticalCenter
        onWidthChanged: tickerAnimation.restart()

        Repeater {
          model: 2
          delegate: Row {
            spacing: Style.space(14)
            rightPadding: Style.space(14)

            Repeater {
              model: root.tickerParties
              delegate: Row {
                required property var modelData
                spacing: Style.space(5)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: modelData.color
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.party + " " + Polls.formatPercent(modelData.percent)
                  color: button.foreground
                  font.family: button.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }
          }
        }
      }

      NumberAnimation {
        id: tickerAnimation
        target: tickerStrip
        property: "x"
        from: 0
        to: -tickerStrip.width / 2
        duration: Math.max(1, tickerStrip.width / 2 / Style.space(35) * 1000)
        loops: Animation.Infinite
        running: root.tickerMode && tickerStrip.width > 0
        // Hold still while hovered so a value can be read.
        paused: running && button.tooltipHovered
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        root.toggle()
      } else if (mouseButton === Qt.MiddleButton) {
        root.refresh()
      } else if (mouseButton === Qt.RightButton && root.bar) {
        Quickshell.execDetached(["xdg-open", root.summary ? root.summary.url : "https://dawum.de/"])
      }
    }
    Accessible.role: Accessible.Button
    Accessible.name: "Germany Polls"
    Accessible.description: root.tooltip
  }
}
