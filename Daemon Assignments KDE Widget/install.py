#!/usr/bin/env python3
"""Install Daemon Assignments, optionally adding its desktop and panel instances."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT / "package"
PLUGIN_ID = "local.daemon.deadlines"


def xdg_directory(variable: str, fallback: Path) -> Path:
    value = os.environ.get(variable)
    return Path(value).expanduser() if value else fallback


def require_command(*names: str) -> str:
    for name in names:
        command = shutil.which(name)
        if command:
            return command
    raise RuntimeError("Required command is missing: " + " or ".join(names))


def plasma_call(qdbus: str, method: str, *arguments: str) -> bytes:
    result = subprocess.run(
        [qdbus, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell." + method, *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError("Plasma D-Bus call failed: " + (detail or method))
    return result.stdout


def backup_layout(qdbus: str, config_directory: Path) -> Path:
    # Obtain the live serialized layout before making any placement changes.
    # Keep it private: it can include settings belonging to unrelated widgets.
    layout = plasma_call(qdbus, "dumpCurrentLayoutJS")
    if not layout.strip():
        raise RuntimeError("Plasma returned an empty layout; placement was cancelled.")
    stamp = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
    destination = ROOT / "backups" / (stamp + "-" + uuid.uuid4().hex[:8])
    destination.mkdir(parents=True, mode=0o700)
    destination.chmod(0o700)
    live_config = config_directory / "plasma-org.kde.plasma.desktop-appletsrc"
    if live_config.is_file():
        saved_config = destination / live_config.name
        shutil.copy2(live_config, saved_config)
        saved_config.chmod(0o600)
    saved_layout = destination / "layout.js"
    saved_layout.write_bytes(layout)
    saved_layout.chmod(0o600)
    return destination


def placement_script() -> str:
    # Pass this as one subprocess argument, without a shell or command substitution.
    return r'''
var pluginId = "local.daemon.deadlines";
var currentDesktops = desktopsForActivity(currentActivity());
var desktop = null;
for (var i = 0; i < currentDesktops.length; ++i) {
    if (currentDesktops[i].screen === 0) { desktop = currentDesktops[i]; break; }
}
if (!desktop) { throw new Error("No current desktop was found on screen 0."); }
var availablePanels = panels();
var panel = null;
for (var i = 0; i < availablePanels.length; ++i) {
    if (availablePanels[i].screen === 0) {
        if (!panel || availablePanels[i].location === "bottom") panel = availablePanels[i];
        if (panel.location === "bottom") break;
    }
}
if (!panel) { throw new Error("No existing panel was found on screen 0."); }
var desktopWidgets = desktop.widgets(pluginId);
var panelWidgets = panel.widgets(pluginId);
var desktopWidget = desktopWidgets.length ? desktopWidgets[0] : null;
var panelWidget = panelWidgets.length ? panelWidgets[0] : null;
var createdDesktop = false;
var createdPanel = false;
if (!desktopWidget) {
    var screen = screenGeometry(desktop.screen);
    var width = Math.min(460, Math.max(320, screen.width - 40));
    var height = Math.min(650, Math.max(420, screen.height - 120));
    var occupied = desktop.widgets();
    var candidates = [[200,130],[40,130],[Math.max(40, (screen.width-width)/2),130],[40,40],[Math.max(40,screen.width-width-40),340]];
    var x = 40;
    var y = 40;
    for (var c = 0; c < candidates.length; ++c) {
        var cx = Math.max(20, Math.min(candidates[c][0], screen.width-width-20));
        var cy = Math.max(20, Math.min(candidates[c][1], screen.height-height-70));
        var overlaps = false;
        for (var w = 0; w < occupied.length; ++w) {
            var r = occupied[w].geometry;
            if (r && cx < r.x+r.width+12 && cx+width+12 > r.x && cy < r.y+r.height+12 && cy+height+12 > r.y) {
                overlaps = true; break;
            }
        }
        if (!overlaps) { x = cx; y = cy; break; }
    }
    var wasLocked = desktop.locked;
    try {
        if (wasLocked) desktop.locked = false;
        desktopWidget = desktop.addWidget(pluginId, x, y, width, height);
        if (!desktopWidget || !desktopWidget.id) throw new Error("Could not add the desktop widget.");
        createdDesktop = true;
    } finally {
        if (wasLocked) desktop.locked = true;
    }
}
if (!panelWidget) {
    var insertionIndex = -1;
    var existing = panel.widgets();
    for (var w = 0; w < existing.length; ++w) {
        if (existing[w].type === "org.kde.plasma.systemtray") {
            insertionIndex = existing[w].index; break;
        }
    }
    var wasLocked = panel.locked;
    try {
        if (wasLocked) panel.locked = false;
        panelWidget = panel.addWidget(pluginId);
        if (!panelWidget || !panelWidget.id) throw new Error("Could not add the panel widget.");
        if (insertionIndex >= 0) panelWidget.index = insertionIndex;
        createdPanel = true;
    } finally {
        if (wasLocked) panel.locked = true;
    }
}
print(JSON.stringify({desktopWidget:desktopWidget.id,panelWidget:panelWidget.id,createdDesktop:createdDesktop,createdPanel:createdPanel}));
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--place", action="store_true",
        help="Also add one instance to the current desktop and one to the existing screen-0 panel; saves a layout backup first.",
    )
    args = parser.parse_args()
    if not (PACKAGE / "metadata.json").is_file():
        raise RuntimeError("The package directory is missing. Keep install.py next to package/.")
    metadata = json.loads((PACKAGE / "metadata.json").read_text(encoding="utf-8"))
    if metadata.get("KPlugin", {}).get("Id") != PLUGIN_ID:
        raise RuntimeError("Unexpected widget package identity.")
    package_tool = require_command("kpackagetool6")
    qdbus = require_command("qdbus-qt6", "qdbus6", "qdbus") if args.place else None
    data_directory = xdg_directory("XDG_DATA_HOME", Path.home() / ".local" / "share")
    config_directory = xdg_directory("XDG_CONFIG_HOME", Path.home() / ".config")
    installed_package = data_directory / "plasma" / "plasmoids" / PLUGIN_ID
    operation = "-u" if installed_package.exists() else "-i"
    subprocess.run([package_tool, "-t", "Plasma/Applet", operation, str(PACKAGE)], check=True)
    notification_source = ROOT / "daemon-assignments.notifyrc"
    if not notification_source.is_file():
        raise RuntimeError("daemon-assignments.notifyrc is missing from this source folder.")
    notifications_directory = data_directory / "knotifications6"
    notifications_directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(notification_source, notifications_directory / notification_source.name)
    print("Daemon Assignments installed for the current user.")
    if args.place:
        assert qdbus is not None
        backup = backup_layout(qdbus, config_directory)
        print("Layout backup saved to " + str(backup))
        result = plasma_call(qdbus, "evaluateScript", placement_script())
        try:
            placement = json.loads(result.decode("utf-8", "replace").strip())
            if not placement.get("desktopWidget") or not placement.get("panelWidget"):
                raise ValueError("Missing widget identifiers")
        except (ValueError, AttributeError) as error:
            raise RuntimeError("Plasma did not confirm both placements. The saved layout backup is available; rerunning --place is safe.") from error
        print("Desktop widget " + str(placement["desktopWidget"]) + "; panel widget " + str(placement["panelWidget"]) + ".")
        print("Desktop and panel instances are ready; assignments are shared between them.")
    else:
        print("Add Daemon Assignments through KDE's Add Widgets menu, or rerun with --place.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print("Installation failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
