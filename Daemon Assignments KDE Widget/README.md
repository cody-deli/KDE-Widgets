# Daemon Assignments

A native KDE Plasma widget styled for Daemon KDE 2.0: burgundy and charcoal surfaces, continuous cyan outlines, coral urgency indicators, diagonally clipped corners with fully connected borders, and your KDE system font.

The same widget automatically becomes a **deadline stack on the desktop** and a **countdown companion on a panel**. Both instances share the same local assignments. This folder includes the widget source and a separate snapshot of your current assignments in `personal-data/`. Installing on this computer keeps using the live data in `~/.config/daemon-assignments.ini`.

## Requirements

- KDE Plasma 6 with Qt 6.5 or later.
- The standard Qt Quick Controls, Qt Core, Kirigami, Plasma, and KDE notification QML modules.
- Python 3 and `kpackagetool6` for the installer.
- `qdbus-qt6`, `qdbus6`, or Qt 6's `qdbus` for automatic placement.
- Python's `PySide6` module for the optional `data_tool.py` import/export utility and test harnesses only. The widget itself and installer do not require Python Qt bindings.

There is no server, account, API key, or background service to configure. Rajdhani is the intended font when it is already selected in your KDE settings.

## Install

Keep this folder's files together, then run:

```sh
python3 install.py --place
```

`Daemon Assignments.plasmoid` is also included as the standalone widget bundle. The command above is recommended because it also installs the notification event definition and can place the widget on the desktop and panel.

The installer installs or updates `local.daemon.deadlines` for the current user. With `--place`, it adds a desktop instance to the current activity on screen 0 and a panel instance before the system tray on an existing screen-0 panel. A new desktop instance requests 460 × 650 pixels, constrained on smaller screens. Existing instances are reused, so rerunning placement does not create duplicates or reposition them.

Before placement, it saves the Plasma applet configuration and live serialized layout under `backups/` beside this README. These private recovery files may contain settings from other widgets; keep them out of shared source archives. The installer does not replace an existing panel or desktop layout.

To install without automatic placement:

```sh
python3 install.py
```

Then open KDE's **Add Widgets** menu, search for **Daemon Assignments**, and add it to your desktop and panel. Use KDE's normal edit mode to resize or reposition the desktop stack.

## Use

- **Add:** click **+** or **Add assignment**. Enter a title and due date, with an optional course and notes.
- **Date-only deadline:** enter `YYYY-MM-DD`. This is the default when no exact submission time is supplied. The widget displays the date and a calendar-day countdown without inventing a deadline time; it becomes overdue after the due day ends.
- **Specific time:** enable the specific-time option and enter a 24-hour `HH:MM` time. Timed deadlines are interpreted in your local timezone, stored as an absolute time, and displayed in local time.
- **Edit:** click an assignment title, or use its menu and choose **Edit assignment**.
- **Complete:** tick its checkbox. Use the **Done** view to find completed assignments and untick one to reopen it.
- **Awaiting marking:** enable this status in the editor for submitted work awaiting a result. It needs no due date and is listed under **Done**, separately labelled **Awaiting marking**. It is excluded from open-deadline counts and reminders.
- **Filter:** switch between **All**, **Today**, **Upcoming**, and **Done**. Active deadlines are grouped by overdue, today, and upcoming, with the earliest deadlines first.
- **Delete:** use an assignment's menu and choose **Delete assignment**. The widget offers **Undo** for its most recently deleted assignment while that widget instance remains open.
- **Panel:** click the panel companion to open its popup, see the next deadline and following assignments, or add and complete work.
- **Reminders:** date-only assignments receive a **Due today** reminder at 09:00 local time on their due day, or when the widget next runs later that day. This is a reminder time, not an assumed submission deadline. For timed assignments, choose 15 minutes, 1 hour, or 1 day before the deadline; the widget can also notify when the deadline arrives. The bell control toggles reminders for the shared assignment list.

Desktop and panel changes synchronize automatically. Notification claims are saved so both instances do not show the same reminder twice.

**Reminders require a running Plasma session with at least one instance of this widget loaded.** They do not run while the computer is off, logged out, or suspended. On resuming, an approaching timed deadline can still trigger a reminder; a just-missed timed deadline is only caught up within a short grace period. A date-only reminder can catch up later on its due day.

## Local data and backup

Assignments, date-only/timed deadlines, awaiting-marking and completed states, reminder preferences, and notification claims live in:

```text
~/.config/daemon-assignments.ini
```

`XDG_CONFIG_HOME` is respected when it is set. This shared file is independent of the per-instance Plasma layout configuration. The `personal-data/daemon-assignments.ini` file is a snapshot of your current local store, including preferences and notification claims. `personal-data/current-assignments.json` is a portable export of its 18 assignments. Keep `personal-data/` private when sharing the widget source. For a consistent restore of the INI snapshot, close/remove both widget instances first, copy the file to the path above, then add the widgets again. Uninstalling the widget does not intentionally delete assignment data.

## Import and export

The separate `personal-data/current-assignments.json` export contains your current 18 assignments as of 2 November 2026. It is not part of the installable widget. The reference images made during design used sample assignments.

The optional data utility requires `PySide6` and uses the same QML model and validation as the widget. To import a supplied JSON file into the shared local store:

```sh
python3 data_tool.py --import-json personal-data/current-assignments.json
```

The importer validates the complete input in an isolated store first and saves a private backup of the existing INI file before changing the live store. Imports merge with existing assignments. Records with an existing `id` or `sourceKey` update that record instead of adding a duplicate; retaining the supplied `sourceKey` values makes repeated imports idempotent. Work already in the store remains available.

To export the current assignments as portable JSON:

```sh
python3 data_tool.py --export-json /path/to/assignments-backup.json
```

Existing export files are preserved unless `--force` is specified. `--storage /path/to/isolated.ini` selects another store for testing; `--backup-dir /path/to/private/backups` changes the import backup directory. These options do not alter KDE's layout.

## Validation

The model and integrated UI checks use isolated temporary settings files:

```sh
python3 tests/test_store.py
python3 tests/test_ui.py
```

The UI integration fixture is `tests/fixtures/assignments-2026-27.json`, the original 18-entry assignment list. It is personal data, so keep this folder private when sharing. It is not embedded in the installable widget.

## Source and removal

`package/` contains the complete QML plasmoid source and metadata. `daemon-assignments.notifyrc` defines the KDE deadline notification event. `install.py` uses only the Python standard library and KDE's installed package/D-Bus tools.

To remove the widget, first remove its desktop and panel instances through KDE, then run:

```sh
kpackagetool6 -t Plasma/Applet -r local.daemon.deadlines
```

The notification definition is installed under `~/.local/share/knotifications6/daemon-assignments.notifyrc` (or `XDG_DATA_HOME`). You may remove that file separately. Keep `daemon-assignments.ini` if you want to retain your assignments.

Licensed under the MIT license; see `LICENSE`.
