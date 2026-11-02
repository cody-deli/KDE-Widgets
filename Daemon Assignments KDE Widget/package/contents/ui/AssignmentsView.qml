import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: view
    required property var store
    property bool panelMode: false
    property bool showAll: false
    property string filterKey: "all"
    readonly property bool editing: editor.visible
    readonly property bool focusMode: panelMode && !showAll
    readonly property var next: store.nextAssignment
    readonly property var rows: {
        store.now;
        const result = [];
        const groups = filterKey === "done" ? [{key:"awaiting-marking",label:"AWAITING MARKING"},{key:"completed",label:"COMPLETED"}] : [{key:"overdue",label:"OVERDUE"},{key:"today",label:"TODAY"},{key:"upcoming",label:"UPCOMING"}];
        for (const group of groups) {
            if (filterKey !== "all" && filterKey !== "done" && group.key !== filterKey) continue;
            const items = store.assignments.filter(function(a) { return store.groupFor(a) === group.key; });
            if (items.length) {
                result.push({kind:"heading",label:group.label,urgent:group.key === "today" || group.key === "overdue"});
                for (const assignment of items) result.push({kind:"assignment",assignment:assignment});
            }
        }
        return result;
    }
    implicitWidth: panelMode ? 420 : 470
    implicitHeight: panelMode ? 560 : 650

    function addAssignment() { editor.openFor(null); }
    function editAssignment(assignment) { editor.openFor(assignment); }

    DaemonFrame { anchors.fill: parent; cornerAccent: true; fillColor: "#210e15"; cut: 22 }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            DaemonButton {
                visible: view.panelMode && view.showAll
                quiet: true
                icon.name: "go-previous"
                help: "Back to next deadline"
                onClicked: view.showAll = false
            }
            Kirigami.Icon { visible: !view.panelMode || !view.showAll; source: "view-task"; color: "#5df4fe"; implicitWidth: 26; implicitHeight: 26 }
            Text { Layout.fillWidth: true; text: "Assignments"; font.pixelSize: 28; font.weight: Font.DemiBold; color: "#5df4fe"; elide: Text.ElideRight }
            DaemonButton { icon.name: "list-add"; help: "Add assignment"; onClicked: view.addAssignment() }
            DaemonButton {
                icon.name: "configure"
                help: "Assignment settings"
                onClicked: settingsMenu.popup()
                Controls.Menu {
                    id: settingsMenu
                    Controls.MenuItem {
                        text: "Deadline reminders"
                        checkable: true
                        checked: view.store.remindersEnabled
                        onTriggered: view.store.setRemindersEnabled(!view.store.remindersEnabled)
                    }
                    Controls.MenuItem { text: "Completed / awaiting marking"; onTriggered: { view.showAll = true; view.filterKey = "done"; } }
                    Controls.MenuSeparator {}
                    Controls.MenuItem { text: "About Daemon Assignments"; onTriggered: about.open() }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: Qt.formatDateTime(view.store.now, "ddd d MMM"); color: "#a1a9b1"; font.pixelSize: 16 }
            Text { text: view.store.openCount + " open"; color: "#a1a9b1"; font.pixelSize: 16 }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#5df4fe"; opacity: 0.4 }
        Text {
            visible: view.store.errorMessage.length > 0
            Layout.fillWidth: true
            text: view.store.errorMessage
            color: "#ff5048"
            font.pixelSize: 15
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.role: Accessible.AlertMessage
        }
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: view.focusMode ? focusComponent : listComponent
        }
        RowLayout {
            visible: view.store.lastDeleted !== null
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Assignment deleted"; color: "#a1a9b1"; font.pixelSize: 15 }
            DaemonButton { text: "Undo"; quiet: true; onClicked: view.store.undoDelete() }
        }
        DaemonButton { Layout.fillWidth: true; icon.name: "list-add"; text: "Add assignment"; onClicked: view.addAssignment() }
        RowLayout {
            Layout.fillWidth: true
            DaemonButton {
                quiet: true
                icon.name: view.store.remindersEnabled ? "notifications" : "notifications-disabled"
                text: view.store.remindersEnabled ? "Reminders on" : "Reminders off"
                help: "Toggle deadline reminders for both widgets"
                implicitHeight: 26
                padding: 3
                tint: "#a1a9b1"
                onClicked: view.store.setRemindersEnabled(!view.store.remindersEnabled)
            }
            Item { Layout.fillWidth: true }
            DaemonButton { visible: view.panelMode; quiet: true; text: view.showAll ? "Next due" : "View all"; implicitHeight: 26; padding: 3; onClicked: { view.showAll = !view.showAll; view.filterKey = "all"; } }
        }
    }

    Component {
        id: listComponent
        ColumnLayout {
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                spacing: 3
                Repeater {
                    model: [{key:"all",label:"All"},{key:"today",label:"Today"},{key:"upcoming",label:"Upcoming"},{key:"done",label:"Done"}]
                    DaemonButton {
                        required property var modelData
                        Layout.fillWidth: true
                        quiet: view.filterKey !== modelData.key
                        text: modelData.label
                        implicitHeight: 32
                        padding: 4
                        onClicked: view.filterKey = modelData.key
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    model: view.rows
                    boundsBehavior: Flickable.StopAtBounds
                    reuseItems: true
                    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
                    delegate: Item {
                        id: rowHost
                        required property var modelData
                        width: list.width - 8
                        height: modelData.kind === "heading" ? 34 : 90
                        Loader { anchors.fill: parent; sourceComponent: rowHost.modelData.kind === "heading" ? headingDelegate : assignmentDelegate }
                        Component {
                            id: headingDelegate
                            Item {
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8
                                    Rectangle { width: 4; height: 14; color: rowHost.modelData.urgent ? "#ff5048" : "#5df4fe"; Layout.alignment: Qt.AlignVCenter }
                                    Text { Layout.fillWidth: true; text: rowHost.modelData.label; color: rowHost.modelData.urgent ? "#ff5048" : "#5df4fe"; font.pixelSize: 15; font.letterSpacing: 2; font.weight: Font.DemiBold }
                                }
                            }
                        }
                        Component {
                            id: assignmentDelegate
                            AssignmentRow { store: view.store; assignment: rowHost.modelData.assignment; onEditRequested: function(assignment) { view.editAssignment(assignment); } }
                        }
                    }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    visible: view.rows.length === 0
                    spacing: 12
                    Kirigami.Icon { Layout.alignment: Qt.AlignHCenter; source: "view-task"; color: "#5df4fe"; implicitWidth: 44; implicitHeight: 44 }
                    Text { Layout.fillWidth: true; text: view.filterKey === "all" ? "All clear." : "Nothing here yet."; color: "#5df4fe"; font.pixelSize: 26; horizontalAlignment: Text.AlignHCenter }
                    Text { Layout.fillWidth: true; text: view.filterKey === "done" ? "Completed work and assignments awaiting marking appear here." : "Add an assignment and its deadline to get started."; color: "#a1a9b1"; font.pixelSize: 16; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
                }
            }
        }
    }

    Component {
        id: focusComponent
        Controls.ScrollView {
            id: focusScroller
            clip: true
            contentWidth: availableWidth
            Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
            ColumnLayout {
                width: focusScroller.availableWidth
                spacing: 10
                DaemonButton {
                    visible: view.store.overdueCount > 0
                    Layout.fillWidth: true
                    tint: "#ff5048"
                    icon.name: "dialog-warning"
                    text: view.store.overdueCount + " overdue · View assignments"
                    onClicked: { view.showAll = true; view.filterKey = "all"; }
                }
                Text { text: view.next && view.store.groupFor(view.next) === "overdue" ? "OVERDUE" : "NEXT DUE"; color: "#a1a9b1"; font.pixelSize: 14; font.letterSpacing: 3 }
                Text { Layout.fillWidth: true; text: view.next ? view.next.title : "All clear."; color: "#5df4fe"; font.pixelSize: 27; font.weight: Font.DemiBold; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; textFormat: Text.PlainText }
                Text { visible: view.next !== null; Layout.fillWidth: true; text: view.next ? view.next.course : ""; color: "#a1a9b1"; font.pixelSize: 16; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                Text { Layout.fillWidth: true; text: { view.store.now; return view.next ? view.store.countdown(view.next) : "No upcoming deadlines"; } color: view.next && (view.store.groupFor(view.next) === "today" || view.store.groupFor(view.next) === "overdue") ? "#ff5048" : "#5df4fe"; font.pixelSize: 32; font.weight: Font.DemiBold; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                Text { visible: view.next !== null; text: view.next ? view.store.dueLabel(view.next) : ""; color: "#a1a9b1"; font.pixelSize: 17 }
                RowLayout {
                    visible: view.next !== null
                    Layout.fillWidth: true
                    DaemonButton { text: "Mark complete"; icon.name: "checkmark"; onClicked: view.store.setCompleted(view.next.id, true) }
                    DaemonButton { text: "Edit"; quiet: true; onClicked: view.editAssignment(view.next) }
                    Item { Layout.fillWidth: true }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#5df4fe"; opacity: 0.3; Layout.topMargin: 4; Layout.bottomMargin: 4 }
                Text { text: "AFTER THAT"; color: "#a1a9b1"; font.pixelSize: 14; font.letterSpacing: 3 }
                Repeater {
                    model: view.store.activeAssignments.filter(function(a) { return (!view.next || a.id !== view.next.id) && view.store.groupFor(a) !== "overdue"; }).slice(0, 2)
                    AssignmentRow {
                        required property var modelData
                        Layout.fillWidth: true
                        store: view.store
                        assignment: modelData
                        onEditRequested: function(assignment) { view.editAssignment(assignment); }
                    }
                }
                Text { visible: view.store.activeAssignments.length <= 1; Layout.fillWidth: true; text: "Your next assignments will appear here."; color: "#a1a9b1"; font.pixelSize: 15; wrapMode: Text.Wrap }
            }
        }
    }

    AssignmentEditor {
        id: editor
        commitAssignment: function(assignment) {
            const saved = view.store.saveAssignment(assignment);
            if (!saved) errorText = view.store.errorMessage;
            return saved;
        }
    }
    Controls.Dialog {
        id: about
        parent: Controls.Overlay.overlay
        title: "Daemon Assignments"
        modal: true
        anchors.centerIn: parent
        width: Math.min(360, parent ? parent.width - 24 : 360)
        implicitHeight: 300
        height: Math.min(300, parent ? parent.height - 24 : 300)
        background: DaemonFrame { cut: 16 }
        standardButtons: Controls.Dialog.Ok
        contentItem: Text {
            text: "Deadline stack + panel companion\n\nYour assignments are saved locally and shared between both widgets.\n\nReminders run while a widget is active in your Plasma session."
            color: "#5df4fe"
            font.pixelSize: 16
            wrapMode: Text.Wrap
        }
    }
}
