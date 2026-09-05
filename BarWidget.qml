import QtQuick
import qs.Commons
import qs.Ui

// Bar icon for Omacircuit. The game itself is a "panel"-kind plugin (a
// FloatingWindow, opened/closed by Panel.qml's own open()/close()/toggle()),
// so this widget owns no state and loads no panel of its own — clicking it
// takes the same IPC route a keybinding would, exactly like the first-party
// widgets do for their own panels. Declaring both "panel" and "bar-widget" in
// the manifest is what keeps shell.toggle() routing through the normal panel
// loader instead of expecting this widget to answer open()/close()/opened.
BarWidget {
  id: root
  moduleName: "io.github.labrat-0.omacircuit"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🏁"
    tooltipText: "Omacircuit"
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(27)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    onPressed: function() {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle " + root.moduleName)
    }
  }
}
