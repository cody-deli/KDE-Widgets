import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.AbstractButton {
    id: badge
    required property var store
    property bool vertical: false
    property bool popupOpen: false
    property var next: store.nextAssignment
    property string countdownText: { store.now; return next ? store.countdown(next, true) : "All clear"; }
    implicitWidth: vertical ? 40 : 190
    implicitHeight: 38
    Layout.minimumWidth: vertical ? 28 : 132
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: vertical ? 60 : 220
    Layout.fillHeight: true
    padding: Math.min(7, Math.max(1, (height - 20) / 2))
    hoverEnabled: true
    Accessible.name: "Assignments, " + store.openCount + " open" + (next ? ", " + next.title + ", " + countdownText : "")
    background: DaemonFrame {
        anchors.margins: 2
        cut: 6
        fillColor: badge.popupOpen || badge.hovered ? "#272932" : "#14101f"
        lineColor: badge.activeFocus || badge.popupOpen || badge.hovered ? "#5df4fe" : "#355d65"
    }
    contentItem: RowLayout {
        spacing: 7
        Kirigami.Icon {
            source: "view-task"
            color: "#5df4fe"
            implicitWidth: Math.min(21, Math.max(14, badge.height - 6))
            implicitHeight: implicitWidth
            Layout.alignment: Qt.AlignCenter
        }
        Text {
            visible: !badge.vertical
            Layout.fillWidth: true
            text: badge.countdownText
            color: badge.next && (badge.store.groupFor(badge.next) === "overdue" || badge.store.groupFor(badge.next) === "today") ? "#ff5048" : "#5df4fe"
            font.family: badge.font.family
            font.pixelSize: 16
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Rectangle {
            visible: badge.store.overdueCount > 0
            width: 6; height: 6; radius: 3
            color: "#fb3048"
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
