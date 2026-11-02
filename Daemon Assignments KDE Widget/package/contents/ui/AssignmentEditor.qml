import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// openFor(null) creates a new assignment; openFor(existing) preserves its fields.
// dueAt is stored as an ISO UTC timestamp, while fields always show local time.
Dialog {
    id: editor

    signal submitted(var assignment)
    signal cancelled()

    property var originalAssignment: null
    // Optional integration hook. A false result keeps the draft open and lets
    // the caller expose a persistence error through errorText.
    property var commitAssignment: null
    property string errorText: ""
    property bool didSubmit: false
    readonly property color cyan: "#5df4fe"
    readonly property color muted: "#a1a9b1"
    readonly property color coral: "#fb3048"
    readonly property color controlFill: "#14101f"

    parent: Overlay.overlay
    width: Math.max(250, Math.min(410, parent ? parent.width - 24 : 410))
    height: Math.min(implicitHeight, parent ? Math.max(180, parent.height - 24) : implicitHeight)
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    padding: 18
    modal: true
    dim: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    title: originalAssignment && originalAssignment.id ? "Edit assignment" : "New assignment"

    palette.text: cyan
    palette.windowText: cyan
    palette.buttonText: cyan
    palette.base: controlFill
    palette.window: "#210e15"
    palette.highlight: "#355d65"
    palette.highlightedText: cyan

    function pad(value) {
        return String(value).padStart(2, "0");
    }

    function openFor(assignment) {
        originalAssignment = assignment ? Object.assign({}, assignment) : null;
        didSubmit = false;
        errorText = "";
        titleField.text = assignment ? String(assignment.title || "") : "";
        courseField.text = assignment ? String(assignment.course || "") : "";
        notesField.text = assignment ? String(assignment.notes || "") : "";
        awaitingMarking.checked = assignment ? assignment.status === "awaiting-marking" : false;
        specificTime.checked = assignment ? !assignment.dateOnly && !!assignment.dueAt : false;
        var deadline = assignment ? new Date(assignment.dueAt) : new Date();
        if (isNaN(deadline.getTime())) deadline = new Date();
        if (!assignment) {
            deadline.setDate(deadline.getDate() + 1);
            deadline.setHours(17, 0, 0, 0);
        }
        dateField.text = deadline.getFullYear() + "-" + pad(deadline.getMonth() + 1) + "-" + pad(deadline.getDate());
        if (assignment && assignment.dateOnly && assignment.dueDate) dateField.text = String(assignment.dueDate);
        if (awaitingMarking.checked) dateField.text = "";
        timeField.text = pad(deadline.getHours()) + ":" + pad(deadline.getMinutes());
        remindersCheck.checked = assignment ? assignment.reminders !== false : true;
        var lead = assignment && assignment.reminderMinutes !== undefined ? Number(assignment.reminderMinutes) : 60;
        var index = reminderOptions.indexOf(lead);
        reminderChoice.currentIndex = index >= 0 ? index : 1;
        open();
    }

    // Round-trip every local component: catches 31 February and local times
    // skipped by daylight-saving changes instead of silently normalising them.
    function localDeadline(dateText, timeText) {
        var dateParts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateText.trim());
        var timeParts = /^(\d{2}):(\d{2})$/.exec(timeText.trim());
        if (!dateParts || !timeParts) return null;
        var year = Number(dateParts[1]);
        var month = Number(dateParts[2]);
        var day = Number(dateParts[3]);
        var hours = Number(timeParts[1]);
        var minutes = Number(timeParts[2]);
        if (year < 1900 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31 || hours > 23 || minutes > 59) return null;
        var parsed = new Date(year, month - 1, day, hours, minutes, 0, 0);
        if (parsed.getFullYear() !== year || parsed.getMonth() !== month - 1 || parsed.getDate() !== day || parsed.getHours() !== hours || parsed.getMinutes() !== minutes) return null;
        return parsed;
    }

    function submitAssignment() {
        var assignmentTitle = titleField.text.trim();
        if (!assignmentTitle) {
            errorText = "Give the assignment a title.";
            titleField.forceActiveFocus();
            return false;
        }
        var deadline = awaitingMarking.checked ? null : localDeadline(dateField.text, specificTime.checked ? timeField.text : "23:59");
        if (!awaitingMarking.checked && !deadline) {
            errorText = specificTime.checked ? "Enter a valid date (YYYY-MM-DD) and local time (HH:MM)." : "Enter a valid due date (YYYY-MM-DD).";
            dateField.forceActiveFocus();
            return false;
        }
        if (deadline && !specificTime.checked) deadline.setSeconds(59, 999);
        var assignment = originalAssignment ? Object.assign({}, originalAssignment) : {};
        assignment.title = assignmentTitle;
        assignment.course = courseField.text.trim();
        assignment.status = awaitingMarking.checked ? "awaiting-marking" : "active";
        assignment.dateOnly = !awaitingMarking.checked && !specificTime.checked;
        assignment.dueDate = assignment.dateOnly ? dateField.text.trim() : "";
        assignment.dueAt = deadline ? deadline.toISOString() : "";
        assignment.notes = notesField.text.trim();
        assignment.reminders = !awaitingMarking.checked && remindersCheck.checked;
        assignment.reminderMinutes = reminderOptions[reminderChoice.currentIndex];
        errorText = "";
        if (typeof commitAssignment === "function" && commitAssignment(assignment) === false) {
            didSubmit = false;
            return false;
        }
        didSubmit = true;
        submitted(assignment);
        close();
        return true;
    }

    readonly property var reminderOptions: [15, 60, 1440]

    onOpened: {
        titleField.forceActiveFocus();
        titleField.selectAll();
    }
    onClosed: {
        if (!didSubmit) cancelled();
    }

    background: DaemonFrame {
        cut: 16
        cornerAccent: true
    }

    header: Item {
        implicitHeight: 58
        Label {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            text: editor.title
            color: editor.cyan
            font.pointSize: editor.font.pointSize + 3
            font.bold: true
            elide: Text.ElideRight
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 1
            color: editor.cyan
            opacity: 0.35
        }
    }

    contentItem: ScrollView {
        id: scroller
        implicitHeight: form.implicitHeight
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: form
            width: scroller.availableWidth
            spacing: 7

            Label {
                visible: editor.errorText.length > 0
                Layout.fillWidth: true
                text: editor.errorText
                color: editor.coral
                wrapMode: Text.Wrap
                Accessible.role: Accessible.AlertMessage
            }

            Label { text: "Assignment title *"; color: editor.cyan }
            EditorField {
                id: titleField
                objectName: "assignmentTitle"
                Layout.fillWidth: true
                placeholderText: "e.g. Database report"
                maximumLength: 160
                Accessible.name: "Assignment title, required"
                onAccepted: courseField.forceActiveFocus()
            }

            Label { text: "Course"; color: editor.cyan; Layout.topMargin: 4 }
            EditorField {
                id: courseField
                objectName: "assignmentCourse"
                Layout.fillWidth: true
                placeholderText: "Optional"
                maximumLength: 100
                Accessible.name: "Course"
                onAccepted: awaitingMarking.checked ? notesField.forceActiveFocus() : dateField.forceActiveFocus()
            }

            EditorCheckBox {
                id: awaitingMarking
                objectName: "assignmentAwaitingMarking"
                text: "Awaiting marking · no deadline"
                Layout.fillWidth: true
                Layout.topMargin: 4
            }
            EditorCheckBox {
                id: specificTime
                objectName: "assignmentSpecificTime"
                text: "Specific time"
                visible: !awaitingMarking.checked
                Layout.fillWidth: true
            }

            RowLayout {
                visible: !awaitingMarking.checked
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    Label {
                        Layout.fillWidth: true
                        text: "Due date · YYYY-MM-DD *"
                        color: editor.cyan
                        font.pointSize: editor.font.pointSize - 1
                        wrapMode: Text.Wrap
                    }
                    EditorField {
                        id: dateField
                        objectName: "assignmentDate"
                        Layout.fillWidth: true
                        placeholderText: "2026-10-28"
                        maximumLength: 10
                        inputMethodHints: Qt.ImhDate
                        Accessible.name: "Due date, year dash month dash day"
                        onAccepted: specificTime.checked ? timeField.forceActiveFocus() : notesField.forceActiveFocus()
                    }
                }
                ColumnLayout {
                    visible: specificTime.checked
                    Layout.preferredWidth: 106
                    spacing: 7
                    Label { text: "Time · HH:MM *"; color: editor.cyan; font.pointSize: editor.font.pointSize - 1 }
                    EditorField {
                        id: timeField
                        objectName: "assignmentTime"
                        Layout.fillWidth: true
                        placeholderText: "17:00"
                        maximumLength: 5
                        inputMethodHints: Qt.ImhTime
                        Accessible.name: "Due time, 24-hour hours colon minutes"
                        onAccepted: editor.submitAssignment()
                    }
                }
            }
            Label {
                visible: !awaitingMarking.checked
                Layout.fillWidth: true
                text: specificTime.checked ? "Local time · 24-hour clock" : "Date only · no specific submission time"
                color: editor.muted
                font.pointSize: editor.font.pointSize - 1
                wrapMode: Text.Wrap
            }

            Label { text: "Notes"; color: editor.cyan; Layout.topMargin: 4 }
            TextArea {
                id: notesField
                objectName: "assignmentNotes"
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                placeholderText: "Optional details or submission link"
                color: editor.cyan
                placeholderTextColor: editor.muted
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                Accessible.name: "Assignment notes"
                background: Rectangle {
                    color: editor.controlFill
                    border.color: notesField.activeFocus ? editor.cyan : "#355d65"
                    border.width: notesField.activeFocus ? 2 : 1
                }
            }

            EditorCheckBox {
                id: remindersCheck
                objectName: "assignmentReminders"
                text: specificTime.checked ? "Remind me before the deadline" : "Remind me on the due date (09:00)"
                checked: true
                enabled: !awaitingMarking.checked
                Layout.fillWidth: true
                Layout.topMargin: 3
            }
            ComboBox {
                id: reminderChoice
                objectName: "assignmentReminderLead"
                visible: specificTime.checked && !awaitingMarking.checked
                Layout.fillWidth: true
                enabled: !awaitingMarking.checked && remindersCheck.checked
                model: ["15 minutes before", "1 hour before", "1 day before"]
                currentIndex: 1
                Accessible.name: "Reminder advance time"
                background: Rectangle {
                    color: editor.controlFill
                    border.color: reminderChoice.activeFocus ? editor.cyan : "#355d65"
                    border.width: reminderChoice.activeFocus ? 2 : 1
                }
            }
        }
    }

    footer: Item {
        implicitHeight: 66
        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10
            Item { Layout.fillWidth: true }
            EditorButton {
                text: "Cancel"
                onClicked: editor.reject()
            }
            EditorButton {
                objectName: "saveAssignmentButton"
                text: editor.originalAssignment && editor.originalAssignment.id ? "Save changes" : "Add assignment"
                highlighted: true
                onClicked: editor.submitAssignment()
            }
        }
    }

    component EditorField: TextField {
        color: editor.cyan
        placeholderTextColor: editor.muted
        selectByMouse: true
        implicitHeight: 36
        leftPadding: 9
        rightPadding: 9
        background: Rectangle {
            color: editor.controlFill
            border.color: parent.activeFocus ? editor.cyan : "#355d65"
            border.width: parent.activeFocus ? 2 : 1
        }
    }

    component EditorCheckBox: CheckBox {
        id: check
        spacing: 9
        opacity: enabled ? 1 : 0.45
        indicator: Rectangle {
            implicitWidth: 20
            implicitHeight: 20
            x: 0
            y: Math.round((parent.height - height) / 2)
            color: editor.controlFill
            border.width: check.activeFocus ? 2 : 1
            border.color: editor.cyan
            Text {
                anchors.centerIn: parent
                text: check.checked ? "✓" : ""
                color: editor.cyan
                font.pointSize: editor.font.pointSize
            }
        }
        contentItem: Text {
            text: check.text
            font: check.font
            color: editor.cyan
            leftPadding: check.indicator.width + check.spacing
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    component EditorButton: Button {
        id: action
        implicitHeight: 36
        implicitWidth: Math.max(82, contentItem.implicitWidth + 24)
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            text: action.text
            font: action.font
            color: editor.cyan
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: action.down ? "#355d65" : action.hovered || action.highlighted ? "#272932" : editor.controlFill
            border.color: action.activeFocus || action.highlighted || action.hovered ? editor.cyan : "#355d65"
            border.width: action.activeFocus ? 2 : 1
        }
    }
}
