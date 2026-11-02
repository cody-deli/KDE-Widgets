import QtQuick
import QtCore

// Every applet instance opens the same QSettings file. Plasma instances share
// one GUI event loop, so a sync/read/mutate/write operation is uninterrupted.
QtObject {
    id: root

    property url storageLocation: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation).toString() + "/daemon-assignments.ini"
    readonly property string storageUrl: storageLocation.toString()
    readonly property string storagePath: decodeURIComponent(storageUrl.replace(/^file:\/\//, ""))
    property var now: new Date()
    property bool clockEnabled: true
    property bool notificationsEnabled: true
    property string errorMessage: ""
    property bool readOnly: false
    property var assignments: []
    property bool remindersEnabled: true
    property var lastDeleted: null
    property string _snapshot: ""
    property var _state: ({ version: 1, revision: 0, assignments: [], remindersEnabled: true, reminderClaims: {} })
    readonly property var activeAssignments: assignments.filter(function(a) { return !a.completed && a.status !== "awaiting-marking"; })
    readonly property var awaitingMarkingAssignments: assignments.filter(function(a) { return !a.completed && a.status === "awaiting-marking"; })
    readonly property var completedAssignments: assignments.filter(function(a) { return a.completed; })
    readonly property int openCount: activeAssignments.length
    readonly property int overdueCount: activeAssignments.filter(function(a) { return new Date(a.dueAt).getTime() < root.now.getTime(); }).length
    readonly property int todayCount: activeAssignments.filter(function(a) { return root.groupFor(a) === "today"; }).length
    readonly property var nextUpcomingAssignment: activeAssignments.find(function(a) { return new Date(a.dueAt).getTime() >= root.now.getTime(); }) || null
    readonly property var nextAssignment: nextUpcomingAssignment || (activeAssignments.length ? activeAssignments[0] : null)
    signal reminderDue(string assignmentId, string title, string body)

    property Settings _settings: Settings {
        location: root.storageLocation
        category: "Assignments"
    }
    property Timer _refreshTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (root.clockEnabled)
                root.now = new Date();
            root.reload();
        }
    }
    property Timer _reminderTimer: Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.checkReminders()
    }

    Component.onCompleted: reload()

    function _emptyState() {
        return { version: 1, revision: 0, assignments: [], remindersEnabled: true, reminderClaims: {} };
    }

    function _clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function _sort(items) {
        return items.sort(function(a, b) {
            var rankA = a.completed ? 2 : a.status === "awaiting-marking" ? 1 : 0;
            var rankB = b.completed ? 2 : b.status === "awaiting-marking" ? 1 : 0;
            if (rankA !== rankB)
                return rankA - rankB;
            if (a.status === "awaiting-marking" && b.status === "awaiting-marking" && !a.completed)
                return a.title.localeCompare(b.title);
            if (a.completed && b.completed)
                return (b.completedAt || "").localeCompare(a.completedAt || "");
            return new Date(a.dueAt).getTime() - new Date(b.dueAt).getTime() || a.title.localeCompare(b.title);
        });
    }

    function _dateOnlyDate(text) {
        var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text || ""));
        if (!match)
            return null;
        var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 23, 59, 59, 999);
        return date.getFullYear() === Number(match[1]) && date.getMonth() === Number(match[2]) - 1 && date.getDate() === Number(match[3]) ? date : null;
    }

    function _calendarDay(date) {
        return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000;
    }

    function _validateState(value) {
        if (!value || value.version !== 1 || !Array.isArray(value.assignments))
            throw new Error("Unsupported assignment data format.");
        var ids = {};
        value.assignments.forEach(function(a) {
            if (!a || typeof a.id !== "string" || !a.id || ids[a.id] || typeof a.title !== "string" || !a.title.trim())
                throw new Error("An assignment in the saved file is invalid.");
            a.status = a.status || "active";
            if (a.status === "in-progress")
                a.status = "active";
            if (a.status !== "active" && a.status !== "awaiting-marking")
                throw new Error("An assignment status is invalid.");
            a.dateOnly = !!a.dateOnly;
            a.dueDate = typeof a.dueDate === "string" ? a.dueDate : "";
            a.sourceKey = typeof a.sourceKey === "string" ? a.sourceKey : "";
            if (a.status === "awaiting-marking") {
                a.dueAt = "";
                a.dateOnly = false;
                a.dueDate = "";
            } else if (a.dateOnly) {
                var dateOnlyDate = root._dateOnlyDate(a.dueDate);
                if (!dateOnlyDate)
                    throw new Error("An assignment due date is invalid.");
                // Recalculate in the current local timezone without displaying
                // this internal end-of-day ordering value as a deadline time.
                a.dueAt = dateOnlyDate.toISOString();
            } else if (typeof a.dueAt !== "string" || !a.dueAt || !Number.isFinite(new Date(a.dueAt).getTime())) {
                throw new Error("An assignment due time is invalid.");
            }
            ids[a.id] = true;
            a.course = typeof a.course === "string" ? a.course : "";
            a.notes = typeof a.notes === "string" ? a.notes : "";
            a.completed = !!a.completed;
            a.reminders = a.reminders !== false;
            a.reminderMinutes = Number.isFinite(a.reminderMinutes) ? Math.max(0, Math.min(10080, a.reminderMinutes)) : 60;
        });
        value.remindersEnabled = value.remindersEnabled !== false;
        if (!value.reminderClaims || typeof value.reminderClaims !== "object" || Array.isArray(value.reminderClaims))
            value.reminderClaims = {};
        value.revision = Number.isFinite(value.revision) ? value.revision : 0;
        return value;
    }

    function _readState() {
        _settings.sync();
        var raw = String(_settings.value("state", ""));
        try {
            var state = raw ? _validateState(JSON.parse(raw)) : _emptyState();
            readOnly = false;
            return { state: state, raw: raw };
        } catch (error) {
            readOnly = true;
            errorMessage = "Saved assignments could not be read. The original file has been preserved: " + storagePath;
            console.warn("Daemon Assignments:", error);
            return null;
        }
    }

    function _adopt(state, raw) {
        _state = state;
        _snapshot = raw;
        assignments = _sort(_clone(state.assignments));
        remindersEnabled = state.remindersEnabled;
    }

    function reload() {
        var wasReadOnly = readOnly;
        var loaded = _readState();
        if (!loaded)
            return false;
        if (loaded.raw !== _snapshot || wasReadOnly) {
            errorMessage = "";
            _adopt(loaded.state, loaded.raw);
        }
        return true;
    }

    function _mutate(operation) {
        errorMessage = "";
        var loaded = _readState();
        if (!loaded)
            return false;
        var state = loaded.state;
        if (operation(state) === false)
            return false;
        state.revision += 1;
        var raw = JSON.stringify(state);
        _settings.setValue("state", raw);
        _settings.sync();
        _adopt(state, raw);
        return true;
    }

    function _index(state, id) {
        return state.assignments.findIndex(function(a) { return a.id === id; });
    }

    function _clearClaims(state, id) {
        Object.keys(state.reminderClaims).forEach(function(key) {
            if (key.indexOf(id + "|") === 0)
                delete state.reminderClaims[key];
        });
    }

    function saveAssignment(draft) {
        return _mutate(function(state) {
            var index = draft.id ? _index(state, draft.id) : draft.sourceKey ? state.assignments.findIndex(function(a) { return a.sourceKey === draft.sourceKey; }) : -1;
            if (draft.id && index < 0) {
                root.errorMessage = "This assignment was deleted in another widget.";
                return false;
            }
            var previous = index >= 0 ? state.assignments[index] : null;
            function field(name, fallback) {
                return draft[name] !== undefined ? draft[name] : previous && previous[name] !== undefined ? previous[name] : fallback;
            }
            var title = String(field("title", "")).trim();
            var course = String(field("course", "")).trim();
            var notes = String(field("notes", "")).trim();
            var status = String(field("status", "active"));
            if (status === "in-progress")
                status = "active";
            var dateOnly = !!field("dateOnly", false);
            var dueDate = String(field("dueDate", ""));
            var rawDueAt = field("dueAt", "");
            var date = dateOnly ? root._dateOnlyDate(dueDate) : typeof rawDueAt === "string" && rawDueAt ? new Date(rawDueAt) : null;
            var reminderMinutes = Number(field("reminderMinutes", 60));
            var sourceKey = String(field("sourceKey", "")).trim();
            if (!title || title.length > 160) {
                root.errorMessage = "Enter an assignment title (up to 160 characters).";
                return false;
            }
            if (course.length > 120 || notes.length > 4000 || sourceKey.length > 256) {
                root.errorMessage = "Course names can have 120 characters and notes 4,000 characters.";
                return false;
            }
            if (status !== "active" && status !== "awaiting-marking") {
                root.errorMessage = "Choose a valid assignment status.";
                return false;
            }
            if (status !== "awaiting-marking" && (!date || !Number.isFinite(date.getTime()))) {
                root.errorMessage = dateOnly ? "Enter a valid due date." : "Enter a valid due date and time.";
                return false;
            }
            if (!Number.isFinite(reminderMinutes) || reminderMinutes < 0 || reminderMinutes > 10080) {
                root.errorMessage = "Choose a reminder between 0 and 10,080 minutes before the deadline.";
                return false;
            }
            var assignment = {
                id: previous ? previous.id : Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 12),
                title: title,
                course: course,
                dueAt: status === "awaiting-marking" ? "" : date.toISOString(),
                dateOnly: status === "awaiting-marking" ? false : dateOnly,
                dueDate: status === "awaiting-marking" ? "" : dateOnly ? dueDate : "",
                status: status,
                sourceKey: sourceKey,
                notes: notes,
                reminders: field("reminders", true) !== false,
                reminderMinutes: Math.round(reminderMinutes),
                completed: previous ? previous.completed : false,
                completedAt: previous ? previous.completedAt || "" : "",
                createdAt: previous ? previous.createdAt || new Date().toISOString() : new Date().toISOString()
            };
            if (previous && (previous.dueAt !== assignment.dueAt || previous.reminderMinutes !== assignment.reminderMinutes || previous.status !== assignment.status || previous.dateOnly !== assignment.dateOnly))
                _clearClaims(state, assignment.id);
            if (index >= 0)
                state.assignments[index] = assignment;
            else
                state.assignments.push(assignment);
            return true;
        });
    }

    function setCompleted(id, completed) {
        return _mutate(function(state) {
            var index = _index(state, id);
            if (index < 0) {
                root.errorMessage = "This assignment is no longer available.";
                return false;
            }
            state.assignments[index].completed = !!completed;
            state.assignments[index].completedAt = completed ? new Date().toISOString() : "";
            return true;
        });
    }

    function toggleCompleted(id) {
        return _mutate(function(state) {
            var index = _index(state, id);
            if (index < 0) {
                root.errorMessage = "This assignment is no longer available.";
                return false;
            }
            var item = state.assignments[index];
            item.completed = !item.completed;
            item.completedAt = item.completed ? new Date().toISOString() : "";
            return true;
        });
    }

    function removeAssignment(id) {
        return _mutate(function(state) {
            var index = _index(state, id);
            if (index < 0) {
                root.errorMessage = "This assignment is no longer available.";
                return false;
            }
            root.lastDeleted = _clone(state.assignments[index]);
            state.assignments.splice(index, 1);
            _clearClaims(state, id);
            return true;
        });
    }

    function undoDelete() {
        if (!lastDeleted)
            return false;
        var restored = _clone(lastDeleted);
        var result = _mutate(function(state) {
            if (_index(state, restored.id) >= 0)
                return false;
            state.assignments.push(restored);
            return true;
        });
        if (result)
            lastDeleted = null;
        return result;
    }

    function setRemindersEnabled(enabled) {
        return _mutate(function(state) {
            state.remindersEnabled = !!enabled;
            return true;
        });
    }

    function groupFor(item) {
        if (item.completed)
            return "completed";
        if (item.status === "awaiting-marking")
            return "awaiting-marking";
        var due = new Date(item.dueAt);
        if (due.getTime() < now.getTime())
            return "overdue";
        return due.toDateString() === now.toDateString() ? "today" : "upcoming";
    }

    function countdown(item, compact) {
        if (!item)
            return compact ? "No deadlines" : "No upcoming deadlines";
        if (item.completed)
            return "Completed";
        if (item.status === "awaiting-marking")
            return "Awaiting marking";
        if (item.dateOnly) {
            var dayDifference = _calendarDay(_dateOnlyDate(item.dueDate)) - _calendarDay(now);
            if (dayDifference === 0)
                return "Due today";
            if (dayDifference === 1)
                return "Tomorrow";
            if (dayDifference < 0)
                return Math.abs(dayDifference) + (dayDifference === -1 ? " day overdue" : " days overdue");
            return "In " + dayDifference + " days";
        }
        var delta = new Date(item.dueAt).getTime() - now.getTime();
        if (Math.abs(delta) < 60000)
            return delta < 0 ? "Just overdue" : "Due now";
        var minutes = Math.ceil(Math.abs(delta) / 60000);
        var days = Math.floor(minutes / 1440);
        var hours = Math.floor((minutes % 1440) / 60);
        var rest = minutes % 60;
        var text = days ? days + "d" + (hours ? " " + hours + "h" : "") : hours ? hours + "h" + (rest ? " " + rest + "m" : "") : minutes + "m";
        return text + (delta < 0 ? " overdue" : compact ? "" : " left");
    }

    function dueLabel(item) {
        if (!item)
            return "";
        if (item.status === "awaiting-marking")
            return "No deadline";
        if (item.dateOnly)
            return Qt.formatDate(_dateOnlyDate(item.dueDate), "d MMM yyyy");
        return Qt.formatDateTime(new Date(item.dueAt), "d MMM · HH:mm");
    }

    // Claims are saved before emitting. Other desktop/panel instances therefore
    // see the claim before their own next check and never repeat this reminder.
    function checkReminders() {
        if (!notificationsEnabled)
            return;
        var loaded = _readState();
        if (!loaded || !loaded.state.remindersEnabled)
            return;
        var pending = [];
        var timestamp = now.getTime();
        loaded.state.assignments.forEach(function(item) {
            if (item.completed || item.reminders === false || item.status === "awaiting-marking")
                return;
            var delta = new Date(item.dueAt).getTime() - timestamp;
            var stage;
            if (item.dateOnly) {
                var days = root._calendarDay(root._dateOnlyDate(item.dueDate)) - root._calendarDay(root.now);
                stage = days === 0 && root.now.getHours() >= 9 ? "date-today" : "";
            } else {
                stage = delta > 0 && item.reminderMinutes > 0 && delta <= item.reminderMinutes * 60000 ? "before" : delta <= 0 && delta >= -300000 ? "due" : "";
            }
            if (!stage)
                return;
            var key = item.id + "|" + item.dueAt + "|" + item.reminderMinutes + "|" + stage;
            if (!loaded.state.reminderClaims[key])
                pending.push({ key: key, item: item, stage: stage });
        });
        if (!pending.length)
            return;
        var claimed = [];
        var saved = _mutate(function(state) {
            pending.forEach(function(entry) {
                if (!state.reminderClaims[entry.key]) {
                    state.reminderClaims[entry.key] = timestamp;
                    claimed.push(entry);
                }
            });
            return claimed.length > 0;
        });
        if (saved) {
            claimed.forEach(function(entry) {
                var item = entry.item;
                root.reminderDue(item.id, item.title, (item.course ? item.course + " · " : "") + root.dueLabel(item) + "\n" + (entry.stage === "due" ? "Due now" : entry.stage === "date-today" ? "Due today" : root.countdown(item)));
            });
        }
    }
}
