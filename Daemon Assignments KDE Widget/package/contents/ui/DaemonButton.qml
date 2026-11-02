import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Button {
    id: button
    property bool quiet: false
    property string help: ""
    property color tint: "#5df4fe"
    implicitHeight: 34
    implicitWidth: Math.max(34, contentItem.implicitWidth + 20)
    padding: 8
    hoverEnabled: true
    Accessible.name: text.length ? text : help
    background: DaemonFrame {
        cut: 5
        fillColor: button.down ? "#355d65" : (button.hovered ? "#272932" : (button.quiet ? "transparent" : "#14101f"))
        lineColor: button.activeFocus || button.hovered || !button.quiet ? button.tint : "transparent"
        opacity: button.enabled ? 1 : 0.4
    }
    contentItem: RowLayout {
        spacing: 7
        Kirigami.Icon {
            visible: button.icon.name.length > 0
            source: button.icon.name
            color: button.tint
            implicitWidth: 18
            implicitHeight: 18
            Layout.alignment: Qt.AlignVCenter
        }
        Text {
            visible: button.text.length > 0
            text: button.text
            color: button.tint
            font: button.font
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }
    }
    Controls.ToolTip.visible: hovered && help.length > 0
    Controls.ToolTip.text: help
    Controls.ToolTip.delay: 600
}
