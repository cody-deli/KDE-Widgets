import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.notification

PlasmoidItem {
    id: root
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || Plasmoid.formFactor === PlasmaCore.Types.Vertical
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.icon: "view-task"
    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    switchWidth: 320
    switchHeight: 320
    toolTipMainText: "Daemon Assignments"
    toolTipSubText: assignmentStore.openCount === 0 ? "All clear. Add an assignment to get started." : assignmentStore.openCount + " open · " + assignmentStore.overdueCount + " overdue" + (assignmentStore.nextAssignment ? "\n" + assignmentStore.nextAssignment.title + " · " + assignmentStore.dueLabel(assignmentStore.nextAssignment) : "")
    hideOnWindowDeactivate: !(fullRepresentationItem && fullRepresentationItem.editing)

    AssignmentStore {
        id: assignmentStore
        onReminderDue: function(assignmentId, title, body) {
            const notification = notice.createObject(root, { title: title, text: body });
            if (notification) notification.sendEvent();
        }
    }
    Component {
        id: notice
        Notification {
            componentName: "daemon-assignments"
            eventId: "deadline"
            iconName: "view-task"
            flags: Notification.CloseOnTimeout
            autoDelete: true
        }
    }
    compactRepresentation: PanelBadge {
        store: assignmentStore
        vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        popupOpen: root.expanded
        onClicked: root.expanded = !root.expanded
    }
    fullRepresentation: AssignmentsView {
        store: assignmentStore
        panelMode: root.inPanel
        Layout.minimumWidth: 370
        Layout.minimumHeight: 420
        Layout.preferredWidth: root.inPanel ? 420 : 470
        Layout.preferredHeight: root.inPanel ? 560 : 650
    }
}
