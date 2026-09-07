import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.loupibe.omarchy-wifi-privacy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string cliPath: Qt.resolvedUrl("bin/omarchy-wifi-privacy").toString().replace(/^file:\/\//, "")
  readonly property int refreshIntervalSec: (settings && settings.refreshIntervalSec) ? settings.refreshIntervalSec : 10

  property var privacyStatus: Model.defaultStatus()
  property bool actionRunning: false

  function open() {
    root.controller.show()
    refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // 0-ms fresh data on popup open
  onOpenedChanged: {
    if (opened) {
      refresh()
    }
  }

  // Destruction cleanup: kill running subprocesses to prevent orphans on reload
  Component.onDestruction: {
    if (statusProcess.running) statusProcess.kill()
    if (actionProcess.running) actionProcess.kill()
    statusWatchdog.stop()
    actionWatchdog.stop()
    pollTimer.stop()
  }

  function refresh() {
    // Prevent overlapping processes
    if (!statusProcess.running) {
      statusWatchdog.restart()
      statusProcess.running = true
    }
  }

  function runCli(action) {
    if (actionRunning || actionProcess.running) return
    actionRunning = true
    actionProcess.command = [root.cliPath, action]
    actionWatchdog.restart()
    actionProcess.running = true
  }

  // Deterministic watchdog timer for recurring status collector (3.0s deadline)
  Timer {
    id: statusWatchdog
    interval: 3000
    repeat: false
    running: false
    onTriggered: {
      if (statusProcess.running) {
        console.warn("wifi-privacy: status collector watchdog timeout reached; terminating process")
        statusProcess.kill()
      }
    }
  }

  // Deterministic watchdog timer for actions (12.0s deadline)
  Timer {
    id: actionWatchdog
    interval: 12000
    repeat: false
    running: false
    onTriggered: {
      if (actionProcess.running) {
        console.warn("wifi-privacy: action watchdog timeout reached; terminating process")
        actionProcess.kill()
      }
      root.actionRunning = false
    }
  }

  // Status collector process
  Process {
    id: statusProcess
    running: false
    command: [root.cliPath, "status", "--json"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        statusWatchdog.stop()
        root.privacyStatus = Model.parseStatus(text, root.privacyStatus)
      }
    }

    onExited: function(exitCode) {
      statusWatchdog.stop()
    }
  }

  // Action process (trust / untrust / randomize)
  Process {
    id: actionProcess
    running: false
    command: []

    onExited: function(exitCode) {
      actionWatchdog.stop()
      root.actionRunning = false
      root.refresh()
    }
  }

  // Lock-screen battery saver: throttle poll interval while screen is locked
  Timer {
    id: pollTimer
    interval: (root.bar && root.bar.screenLocked) ? 10000 : (root.refreshIntervalSec * 1000)
    running: true
    repeat: true
    onTriggered: if (root.opened) root.refresh()
  }

  // Popup panel
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: mainColumn
          width: parent.width
          spacing: Style.space(12)
          topPadding: Style.space(4)
          bottomPadding: Style.space(12)

          // Header
          PanelHero {
            width: parent.width
            title: "Wi-Fi Privacy"
            meta: {
              if (!root.privacyStatus) return "Reading status..."
              if (!root.privacyStatus.active) return "Wi-Fi Disconnected"
              if (root.privacyStatus.is_trusted) return "Trusted Network"
              if (root.privacyStatus.is_mac_randomized) return "Identity Cloaked & Protected"
              return "Connected (Untrusted)"
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰒃"
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                color: root.foreground
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // Active Connection Details
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "CONNECTION DETAILS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              Text {
                textFormat: Text.PlainText
                text: "Network (SSID):"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Item { Layout.fillWidth: true }
              Text {
                textFormat: Text.PlainText
                text: root.privacyStatus && root.privacyStatus.ssid ? root.privacyStatus.ssid : "--"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            RowLayout {
              width: parent.width
              Text {
                textFormat: Text.PlainText
                text: "Status:"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Item { Layout.fillWidth: true }
              Text {
                textFormat: Text.PlainText
                text: {
                  if (!root.privacyStatus || !root.privacyStatus.active) return "Inactive"
                  return root.privacyStatus.is_trusted ? "Trusted (Real MAC)" : "Untrusted (Random MAC)"
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // Identity & Anti-Tracking Posture
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "IDENTITY & ANTI-TRACKING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              Text {
                textFormat: Text.PlainText
                text: "Active MAC:"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Item { Layout.fillWidth: true }
              Text {
                textFormat: Text.PlainText
                text: {
                  if (!root.privacyStatus) return "--"
                  var tag = root.privacyStatus.is_mac_randomized ? " [Random]" : " [Hardware]"
                  return root.privacyStatus.current_mac + tag
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.privacyStatus ? root.privacyStatus.is_mac_randomized : false
              }
            }

            RowLayout {
              width: parent.width
              Text {
                textFormat: Text.PlainText
                text: "DHCP Hostname:"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Item { Layout.fillWidth: true }
              Text {
                textFormat: Text.PlainText
                text: {
                  if (!root.privacyStatus) return "--"
                  return root.privacyStatus.dhcp_hostname
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            RowLayout {
              width: parent.width
              Text {
                textFormat: Text.PlainText
                text: "IPv6 Temporary Addr:"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Item { Layout.fillWidth: true }
              Text {
                textFormat: Text.PlainText
                text: root.privacyStatus && root.privacyStatus.ipv6_tempaddr ? "Active (RFC 4941)" : "Standard"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            RowLayout {
              width: parent.width
              Text {
                textFormat: Text.PlainText
                text: "mDNS Broadcast:"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Item { Layout.fillWidth: true }
              Text {
                textFormat: Text.PlainText
                text: root.privacyStatus && root.privacyStatus.avahi_hidden ? "Hidden (Silent)" : "Broadcasting"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // Actions
          Column {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: parent.width
              text: {
                if (!root.privacyStatus || !root.privacyStatus.active) return "No Active Wi-Fi"
                return root.privacyStatus.is_trusted ? "Untrust Network (Switch to Random MAC)" : "Trust Network (Use Hardware MAC)"
              }
              iconText: root.privacyStatus && root.privacyStatus.is_trusted ? "󰌾" : "󰒃"
              enabled: root.privacyStatus && root.privacyStatus.active && !root.actionRunning
              onClicked: {
                if (root.privacyStatus.is_trusted) {
                  root.runCli("untrust")
                } else {
                  root.runCli("trust")
                }
              }
            }

            Button {
              width: parent.width
              text: "Rotate Identity Now (New Random MAC)"
              iconText: "󰑐"
              enabled: root.privacyStatus && root.privacyStatus.active && !root.actionRunning
              onClicked: {
                root.runCli("randomize")
              }
            }

            Button {
              width: parent.width
              text: "Refresh Status"
              iconText: "󰓦"
              enabled: !root.actionRunning
              onClicked: {
                root.refresh()
              }
            }
          }
        }
      }
    }
  }
}
