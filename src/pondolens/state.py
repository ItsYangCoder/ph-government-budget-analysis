"""Single-host SQLite ledger and crash-released advisory lock (macOS/Linux)."""
import fcntl
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path

from .common import ExtractionError, canonical, utcnow


@contextmanager
def locked_state(root, timeout=30):
    root = Path(root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    with (root / 'writer.lock').open('a') as lock:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise ExtractionError('Another local run holds writer.lock; retry later')
                time.sleep(0.05)
        db = sqlite3.connect(root / 'state.sqlite', timeout=30)
        db.row_factory = sqlite3.Row
        try:
            db.executescript('''
            PRAGMA journal_mode=DELETE;
            PRAGMA synchronous=FULL;
            CREATE TABLE IF NOT EXISTS processing (
                processing_key TEXT PRIMARY KEY, source_id TEXT NOT NULL,
                file_sha256 TEXT NOT NULL, config_hash TEXT NOT NULL,
                extractor_version TEXT NOT NULL, status TEXT NOT NULL,
                output_dir TEXT, row_count INTEGER, started_at TEXT, ended_at TEXT,
                error TEXT, origin_filename TEXT, source_location TEXT,
                file_size INTEGER, batch_id TEXT, run_id TEXT);
            CREATE TABLE IF NOT EXISTS sightings (
                id INTEGER PRIMARY KEY, processing_key TEXT, filename TEXT,
                source_location TEXT, batch_id TEXT, run_id TEXT, seen_at TEXT);
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY, processing_key TEXT, run_id TEXT,
                batch_id TEXT, status TEXT, details_json TEXT, recorded_at TEXT);
            ''')
            yield db
        finally:
            db.commit()
            db.close()
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def event(db, key, run, batch, status, details):
    with db:
        db.execute('INSERT INTO events VALUES(NULL,?,?,?,?,?,?)',
                   (key, run, batch, status, canonical(details), utcnow()))
