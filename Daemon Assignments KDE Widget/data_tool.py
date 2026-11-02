#!/usr/bin/env python3
"""Import/export local assignments through the same QML model used by Plasma.

Imports are validated in an isolated store before the target is changed. Existing
data is backed up privately before import; sourceKey makes repeat imports safe.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QCoreApplication, QUrl
from PySide6.QtQml import QQmlComponent, QQmlEngine

ROOT = Path(__file__).resolve().parent
STORE_QML = ROOT / "package/contents/ui/AssignmentStore.qml"


class DataToolError(Exception):
    pass


class QmlStore:
    def __init__(self, storage: Path | None = None):
        self.engine = QQmlEngine()
        self.component = QQmlComponent(self.engine, QUrl.fromLocalFile(str(STORE_QML)))
        if self.component.isError():
            raise DataToolError("The assignment QML model could not load: " + "; ".join(error.toString() for error in self.component.errors()))
        properties = {"notificationsEnabled": False}
        if storage is not None:
            properties["storageLocation"] = QUrl.fromLocalFile(str(storage))
        self.object = self.component.createWithInitialProperties(properties)
        if self.object is None:
            raise DataToolError("The assignment QML model could not be created.")
        self.engine.globalObject().setProperty("store", self.engine.newQObject(self.object))
        if self.evaluate("store.readOnly"):
            raise DataToolError(self.evaluate("store.errorMessage"))

    def evaluate(self, expression):
        value = self.engine.evaluate(expression)
        if value.isError():
            raise DataToolError(value.toString())
        return value.toVariant()

    @property
    def assignments(self):
        return self.evaluate("store.assignments")

    @property
    def storage_path(self):
        return Path(self.evaluate("store.storagePath"))

    def apply(self, original: dict):
        """Use the public model API; retain identifiers already in this store."""
        draft = dict(original)
        before = self.assignments
        matching = next((item for item in before if draft.get("id") and item["id"] == draft["id"]), None)
        if matching is None and draft.get("sourceKey"):
            matching = next((item for item in before if item.get("sourceKey") == draft["sourceKey"]), None)
        if matching is not None:
            draft["id"] = matching["id"]
        else:
            draft.pop("id", None)
        if not self.evaluate("store.saveAssignment(" + json.dumps(draft, ensure_ascii=False) + ")"):
            raise DataToolError(self.evaluate("store.errorMessage") or "The assignment could not be saved.")
        if "completed" in draft:
            if matching is not None:
                saved_id = matching["id"]
            else:
                previous_ids = {item["id"] for item in before}
                saved_id = next(item["id"] for item in self.assignments if item["id"] not in previous_ids)
            if not self.evaluate("store.setCompleted(" + json.dumps(saved_id) + ", " + ("true" if draft["completed"] else "false") + ")"):
                raise DataToolError(self.evaluate("store.errorMessage") or "Completion state could not be saved.")
        return matching is not None


def read_import(path: Path):
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise DataToolError(f"Could not read import JSON: {error}") from error
    if not isinstance(document, dict) or not isinstance(document.get("assignments"), list):
        raise DataToolError("Import JSON must contain an 'assignments' array.")
    records = document["assignments"]
    seen_sources = set()
    seen_ids = set()
    for index, record in enumerate(records, 1):
        if not isinstance(record, dict):
            raise DataToolError(f"Import entry {index} must be an object.")
        for field, seen in (("sourceKey", seen_sources), ("id", seen_ids)):
            identifier = record.get(field)
            if identifier:
                if not isinstance(identifier, str) or identifier in seen:
                    raise DataToolError(f"Import entry {index} has an invalid or duplicate {field}.")
                seen.add(identifier)
        if "completed" in record and not isinstance(record["completed"], bool):
            raise DataToolError(f"Import entry {index} has an invalid completed flag.")
    return records


def validate_import(records):
    # QML performs the validation; a temporary INI ensures no user data changes.
    with tempfile.TemporaryDirectory(prefix=".validate-", dir=ROOT) as staging_dir:
        staged = QmlStore(Path(staging_dir) / "assignments.ini")
        for index, record in enumerate(records, 1):
            try:
                staged.apply(record)
            except DataToolError as error:
                raise DataToolError(f"Import entry {index} is invalid: {error}") from error


def private_backup(source: Path, directory: Path):
    if not source.exists():
        return None
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory.chmod(0o700)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    destination = directory / f"daemon-assignments-{stamp}-{time.time_ns()}.ini"
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb") as output, source.open("rb") as input_file:
            shutil.copyfileobj(input_file, output)
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    return destination


def write_export(destination: Path, records, force: bool):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and not force:
        raise DataToolError("Export file already exists; use --force to replace it.")
    descriptor, temporary_name = tempfile.mkstemp(prefix="." + destination.name + ".", dir=destination.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump({"assignments": records}, output, ensure_ascii=False, indent=2)
            output.write("\n")
        if force:
            os.replace(temporary, destination)
        else:
            # A hard link prevents a race from overwriting a newly created file.
            os.link(temporary, destination)
            temporary.unlink()
    except FileExistsError as error:
        raise DataToolError("Export file already exists; use --force to replace it.") from error
    finally:
        temporary.unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--import-json", type=Path, metavar="PATH")
    action.add_argument("--export-json", type=Path, metavar="PATH")
    parser.add_argument("--storage", type=Path, metavar="INI", help="Use another INI file (for isolated testing).")
    parser.add_argument("--backup-dir", type=Path, metavar="DIR", help="Private backup directory; defaults to this tool's backups/ directory.")
    parser.add_argument("--force", action="store_true", help="Allow replacing an existing JSON export file.")
    args = parser.parse_args(argv)
    application = QCoreApplication.instance() or QCoreApplication([])
    storage = args.storage.expanduser().resolve() if args.storage else None
    try:
        if args.import_json:
            records = read_import(args.import_json.expanduser().resolve())
            validate_import(records)
            store = QmlStore(storage)
            if not records:
                print("Import validated: 0 assignments; no changes made.")
                return 0
            backup_dir = args.backup_dir.expanduser().resolve() if args.backup_dir else ROOT / "backups"
            backup = private_backup(store.storage_path, backup_dir)
            added = updated = 0
            for record in records:
                if store.apply(record):
                    updated += 1
                else:
                    added += 1
            print(f"Import complete: {added} added, {updated} updated.")
            print(f"Assignments: {store.evaluate('store.openCount')} open, {store.evaluate('store.awaitingMarkingAssignments.length')} awaiting marking, {store.evaluate('store.completedAssignments.length')} completed.")
            print("Original data backup: " + str(backup) if backup else "Original data backup: not needed (new store).")
        else:
            store = QmlStore(storage)
            destination = args.export_json.expanduser().resolve()
            if destination == store.storage_path.resolve():
                raise DataToolError("The export path cannot replace the assignment storage file.")
            records = store.assignments
            write_export(destination, records, args.force)
            print(f"Export complete: {len(records)} assignments written to {destination}")
        return 0
    except (DataToolError, OSError, TypeError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
