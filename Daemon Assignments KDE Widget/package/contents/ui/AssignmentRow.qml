import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts

Item {
    id: row
    required property var assignment
    required property var store
    signal editRequested(var assignment)
    signal deleted()
    implicitHeight: 86
    property string group: { store.now; return store.groupFor(assignment); }
    property color statusColor: group === "overdue" || group === "today" ? "#ff5048" : "#a1a9b1"

    Rectangle { anchors.fill: parent; color: "#272932"; opacity: editButton.hovered ? 0.6 : 0 }
    RowLayout {
        anchors.fill: parent
        spacing: 10
        Controls.CheckBox {
            id: done
            checked: row.assignment.completed === true
            implicitWidth: 28
            Layout.alignment: Qt.AlignVCenter
            Accessible.name: (checked ? "Reopen " : "Complete ") + row.assignment.title
            onClicked: row.store.setCompleted(row.assignment.id, !row.assignment.completed)
            indicator: Rectangle {
                x: 2
                y: (done.height - height) / 2
                width: 22; height: 22
                color: done.hovered ? "#355d65" : "#14101f"
                border.width: done.activeFocus ? 2 : 1
                border.color: "#5df4fe"
                Text { anchors.centerIn: parent; text: done.checked ? "✓" : ""; color: "#5df4fe"; font.pixelSize: 18 }
            }
            contentItem: Item {}
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: checked ? "Mark as unfinished" : "Mark complete"
        }
        Controls.AbstractButton {
            id: editButton
            Layout.fillWidth: true
            Layout.fillHeight: true
            hoverEnabled: true
            Accessible.name: "Edit " + row.assignment.title
            onClicked: row.editRequested(row.assignment)
            background: Rectangle { color: "transparent"; border.color: editButton.activeFocus ? "#5df4fe" : "transparent" }
            contentItem: ColumnLayout {
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: row.assignment.title
                    color: row.assignment.completed ? "#a1a9b1" : "#5df4fe"
                    font.family: editButton.font.family
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                    font.strikeout: row.assignment.completed === true
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: row.assignment.course || ""
                    color: "#a1a9b1"
                    font.family: editButton.font.family
                    font.pixelSize: 15
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: row.assignment.title + (row.assignment.notes ? "\n" + row.assignment.notes : "") + "\nClick to edit"
            Controls.ToolTip.delay: 700
        }
        ColumnLayout {
            Layout.preferredWidth: 112
            spacing: 3
            Text {
                Layout.fillWidth: true
                text: row.store.dueLabel(row.assignment)
                color: "#a1a9b1"
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 15
                textFormat: Text.PlainText
            }
            Text {
                Layout.fillWidth: true
                text: { row.store.now; return row.assignment.completed ? "Completed" : row.store.countdown(row.assignment); }
                color: row.assignment.completed ? "#28c775" : row.statusColor
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 15
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
        DaemonButton {
            quiet: true
            icon.name: "overflow-menu"
            help: "Assignment actions"
            implicitWidth: 28
            padding: 4
            onClicked: actions.popup()
            Controls.Menu {
                id: actions
                Controls.MenuItem { text: "Edit assignment"; onTriggered: row.editRequested(row.assignment) }
                Controls.MenuItem { text: row.assignment.completed ? "Reopen" : "Mark complete"; onTriggered: row.store.toggleCompleted(row.assignment.id) }
                Controls.MenuSeparator {}
                Controls.MenuItem { text: "Delete assignment"; onTriggered: { if (row.store.removeAssignment(row.assignment.id)) row.deleted(); } }
            }
        }
    }
    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: "#5df4fe"; opacity: 0.22 }
}
