import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "Polls.js" as Polls
import "GermanyMap.js" as GermanyMap

// Map popout. The bar widget owns fetching; this only presents the parsed
// polls, so opening it never triggers a network request.
//
// Each state is filled with its polling leader's colour. The fill fades for
// narrow leads and for polls older than Polls.staleDays. Hovering a state
// previews its numbers; clicking pins it, clicking outside the map returns to
// the Bundestag.
Panel {
  id: root
  moduleName: "yubinex.germany-polls"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var polls: null
  property double fetchedMs: 0
  property bool fetchFailed: false
  property string selectedParliament: "0"
  property string hoveredParliament: ""

  readonly property string barDisplay: {
    var mode = setting("barDisplay", "leader")
    return mode === "ticker" || mode === "icon" ? mode : "leader"
  }
  readonly property string shownParliament: hoveredParliament || selectedParliament
  readonly property var shown: polls ? polls.parliaments[shownParliament] || null : null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool compactLayout: popup.contentWidth < Style.space(480)
  readonly property real mapScale: mapBox.width / GermanyMap.width
  readonly property real maxPercent: {
    var results = shown ? shown.results : []
    var max = 0
    for (var i = 0; i < results.length; ++i) max = Math.max(max, results[i].percent)
    return Math.max(max, 1)
  }

  function stateFill(parliament) {
    var summary = polls ? polls.parliaments[parliament] : null
    if (!summary || !summary.leader) return Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    var base = Qt.color(summary.leader.color)
    var alpha = Polls.ageDays(summary, Date.now()) > Polls.staleDays
      ? 0.3 : Math.min(1, 0.5 + summary.margin / 20)
    return Qt.rgba(base.r, base.g, base.b, alpha)
  }

  // City states are drawn last, so search from the top of the stack down.
  function parliamentAt(x, y) {
    for (var i = stateRepeater.count - 1; i >= 0; --i) {
      var shape = stateRepeater.itemAt(i)
      if (!shape) continue
      var point = mapBox.mapToItem(shape, x, y)
      if (shape.contains(point)) return shape.parliament
    }
    return ""
  }

  // Write to this widget's shell.json entry so the choice survives restarts.
  function persistSettings(values) {
    var entry = { id: moduleName }
    for (var existing in settings) if (existing !== "id") entry[existing] = settings[existing]
    for (var key in values) entry[key] = values[key]
    settings = entry
    if (hostWidget && "settings" in hostWidget) hostWidget.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function updatedText() {
    if (fetchFailed && fetchedMs <= 0) return "Could not reach DAWUM"
    if (fetchedMs <= 0) return "Loading polls…"
    return "DAWUM · ODbL · fetched " + Qt.formatDateTime(new Date(fetchedMs), "HH:mm")
      + (fetchFailed ? " · last refresh failed" : "")
  }

  onOpenedChanged: if (!opened) { hoveredParliament = ""; selectedParliament = "0" }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    contentWidth: popup.fittedContentWidth(Style.space(600))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)
    focusTarget: keyboardCatcher

    PanelKeyCatcher {
      id: keyboardCatcher
      anchors.fill: parent
      z: -1
      onCloseRequested: root.close()
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: content
        width: scroll.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          Column {
            width: Math.max(0, parent.width - bundestagChip.width)
            spacing: Style.space(2)
            Text {
              text: "GERMANY POLLS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 12
              font.bold: true
            }
            Text {
              width: parent.width
              text: root.shown ? root.shown.shortcut.toUpperCase() : "—"
              elide: Text.ElideRight
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 1.0
            }
            Text {
              width: parent.width
              text: root.shown ? Polls.sourceLine(root.shown) : root.updatedText()
              elide: Text.ElideRight
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 12
            }
          }

          Rectangle {
            id: bundestagChip
            anchors.verticalCenter: parent.verticalCenter
            visible: root.selectedParliament !== "0"
            width: visible ? chipLabel.implicitWidth + Style.space(16) : 0
            height: Style.space(25)
            radius: Style.space(3)
            color: "transparent"
            border.width: 1
            border.color: root.dim
            Text {
              id: chipLabel
              anchors.centerIn: parent
              text: "‹ BUNDESTAG"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 11
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedParliament = "0"
            }
          }
        }

        PanelSeparator { width: parent.width }

        Flow {
          width: parent.width
          spacing: Style.space(18)

          Item {
            id: mapBox
            width: root.compactLayout ? parent.width : Math.round(parent.width * 0.44)
            height: Math.round(width * GermanyMap.height / GermanyMap.width)

            Item {
              width: GermanyMap.width
              height: GermanyMap.height
              transform: Scale { xScale: root.mapScale; yScale: root.mapScale }

              Repeater {
                id: stateRepeater
                model: GermanyMap.states

                delegate: Shape {
                  required property var modelData
                  readonly property string parliament: modelData.parliament
                  width: GermanyMap.width
                  height: GermanyMap.height
                  containsMode: Shape.FillContains
                  preferredRendererType: Shape.CurveRenderer

                  ShapePath {
                    fillRule: ShapePath.OddEvenFill
                    fillColor: root.stateFill(modelData.parliament)
                    strokeColor: root.surface
                    strokeWidth: 1.5 / Math.max(root.mapScale, 0.01)
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: modelData.path }
                  }
                }
              }

              // Outline the shown state on top so neighbours never cover it.
              Repeater {
                model: GermanyMap.states
                delegate: Shape {
                  required property var modelData
                  visible: modelData.parliament === root.shownParliament
                  width: GermanyMap.width
                  height: GermanyMap.height
                  preferredRendererType: Shape.CurveRenderer
                  ShapePath {
                    fillRule: ShapePath.OddEvenFill
                    fillColor: "transparent"
                    strokeColor: root.fg
                    strokeWidth: 2.5 / Math.max(root.mapScale, 0.01)
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: modelData.path }
                  }
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.hoveredParliament ? Qt.PointingHandCursor : Qt.ArrowCursor
              onPositionChanged: function(mouse) { root.hoveredParliament = root.parliamentAt(mouse.x, mouse.y) }
              onExited: root.hoveredParliament = ""
              onClicked: function(mouse) {
                var hit = root.parliamentAt(mouse.x, mouse.y)
                root.selectedParliament = hit && hit !== root.selectedParliament ? hit : "0"
              }
            }
          }

          Column {
            width: root.compactLayout ? parent.width : parent.width - mapBox.width - parent.spacing
            spacing: Style.space(8)

            Repeater {
              model: root.shown ? root.shown.results : []

              delegate: Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(3)

                Row {
                  width: parent.width
                  Text {
                    width: parent.width - percentLabel.implicitWidth
                    text: modelData.party
                    elide: Text.ElideRight
                    color: modelData.other ? root.dim : root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.bold: !modelData.other
                  }
                  Text {
                    id: percentLabel
                    text: Polls.formatPercent(modelData.percent)
                    color: modelData.other ? root.dim : root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 13
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(6)
                  radius: height / 2
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                  Rectangle {
                    width: Math.max(height, parent.width * modelData.percent / root.maxPercent)
                    height: parent.height
                    radius: parent.radius
                    color: modelData.color
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: !root.shown
              text: root.updatedText()
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 13
            }

            Text {
              width: parent.width
              visible: root.shown !== null && root.shown.pollCount > 1
              text: root.shown ? root.shown.institutes.join(", ") : ""
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 11
            }
          }
        }

        Text {
          width: parent.width
          text: "Colour = leading party. Paler = narrower lead or poll older than six months. Hover to preview, click to pin."
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        Row {
          spacing: Style.space(6)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            rightPadding: Style.space(4)
            text: "BAR SHOWS"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 11
            font.bold: true
          }
          Repeater {
            model: [
              { id: "leader", label: "LEADING PARTY" },
              { id: "ticker", label: "TICKER" },
              { id: "icon", label: "ICON ONLY" }
            ]
            delegate: Rectangle {
              required property var modelData
              readonly property bool current: root.barDisplay === modelData.id
              implicitWidth: displayLabel.implicitWidth + Style.space(16)
              implicitHeight: Style.space(25)
              radius: Style.space(3)
              color: current ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16) : "transparent"
              border.width: 1
              border.color: current ? root.fg : root.dim
              Text {
                id: displayLabel
                anchors.centerIn: parent
                text: modelData.label
                color: parent.current ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: 11
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.persistSettings({ barDisplay: modelData.id })
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        Row {
          width: parent.width
          Text {
            width: Math.max(0, parent.width - dawumLink.implicitWidth - Style.space(12))
            text: root.updatedText()
            elide: Text.ElideRight
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 12
          }
          Text {
            id: dawumLink
            text: "OPEN DAWUM ↗"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.bar) root.bar.run("xdg-open " + (root.shown ? root.shown.url : "https://dawum.de/"))
            }
          }
        }
      }
    }
  }
}
