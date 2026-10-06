"""Discovery, stable snapshots, idempotency, quarantine and audit orchestration."""
import hashlib
import json
import os
import shutil
from pathlib import Path
from uuid import uuid4

from . import __version__
from .adapters import extract
from .common import ExtractionError, digest, file_hash, utcnow, validate_config
from .output import build_output, fsync_dir, verify_output, write_json
from .state import event, locked_state


def snapshot(source, stage):
    before = source.stat()
    h = hashlib.sha256()

    with source.open('rb') as incoming, (stage / 'original.bin').open('xb') as outgoing:
        for chunk in iter(lambda: incoming.read(1024 * 1024), b''):
            h.update(chunk)
            outgoing.write(chunk)

        outgoing.flush()
        os.fsync(outgoing.fileno())

    after = source.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ExtractionError(
            'Source changed during snapshot; retry after upload completes'
        )

    # The adapter receives the snapshot, never the mutable incoming file.
    suffix = source.suffix.lower()
    readable = stage / ('readable' + suffix)
    shutil.copyfile(stage / 'original.bin', readable)

    return h.hexdigest(), after.st_size, readable


def run_pipeline(
    config,
    input_root,
    output_root,
    batch_id,
    extractor_version=__version__,
    fault=None,
):
    """fault is a test-only callback; CLI has no crash-injection option."""
    validate_config(config)

    incoming = Path(input_root).resolve()
    root = Path(output_root).resolve()

    if not incoming.is_dir():
        raise ExtractionError(f'Input root does not exist: {incoming}')

    if root == incoming or root.is_relative_to(incoming):
        raise ExtractionError('Output must not be inside input root')

    run_id = uuid4().hex
    results = []

    with locked_state(root, config.get('lock_timeout_seconds', 30)) as db:
        for name in ['.staging', 'committed', 'quarantine', 'audit']:
            (root / name).mkdir(exist_ok=True)

        # An OS crash releases flock. Anything left in staging is unpublished.
        for orphan in (root / '.staging').iterdir():
            if orphan.is_dir():
                os.replace(
                    orphan,
                    root / 'quarantine' / f'orphan-{orphan.name}-{uuid4().hex}',
                )

        for src in config['sources']:
            if not src.get('enabled', True):
                results.append({
                    'source_id': src['source_id'],
                    'status': 'DEFERRED',
                    'reason': src.get('deferred_reason', 'Not enabled'),
                })
                continue

            matches = sorted(
                p for p in incoming.glob(src['glob']) if p.is_file()
            )

            if not matches:
                result = {
                    'source_id': src['source_id'],
                    'status': 'MISSING',
                    'glob': src['glob'],
                }
                results.append(result)
                event(db, None, run_id, batch_id, 'MISSING', result)
                continue

            for path in matches:
                stage = root / '.staging' / uuid4().hex
                key = None

                try:
                    # Record an unsafe input as FAILED and continue with other files.
                    if not path.resolve().is_relative_to(incoming):
                        raise ExtractionError(
                            'Input symlink points outside authorized input root'
                        )

                    stage.mkdir()
                    sha, size, readable = snapshot(path, stage)

                    # Discovery paths and batch identifiers are not extraction semantics.
                    extraction_cfg = {
                        k: v
                        for k, v in src.items()
                        if k not in {
                            'glob',
                            'enabled',
                            'deferred_reason',
                            'source_url',
                            'drive_file_id',
                        }
                    }

                    cfg_hash = digest(extraction_cfg)
                    key = digest([
                        src['source_id'],
                        sha,
                        cfg_hash,
                        extractor_version,
                    ])
                    dest = root / 'committed' / src['source_id'] / key
                    location = src.get('source_url') or str(path)

                    with db:
                        db.execute(
                            'INSERT INTO sightings VALUES(NULL,?,?,?,?,?,?)',
                            (
                                key,
                                path.name,
                                location,
                                batch_id,
                                run_id,
                                utcnow(),
                            ),
                        )

                    previous = db.execute(
                        'SELECT * FROM processing WHERE processing_key=?',
                        (key,),
                    ).fetchone()

                    valid = verify_output(dest, key) if dest.exists() else None

                    if valid:
                        if previous is None or previous['status'] != 'SUCCESS':
                            # Recover publication completed before the state commit.
                            commit_state(db, valid, dest)
                            status = 'RECOVERED'
                        else:
                            status = 'SKIPPED'

                        result = {
                            'source_id': src['source_id'],
                            'file': path.name,
                            'status': status,
                            'processing_key': key,
                            'row_count': valid['row_count'],
                            'flagged_records': valid['flagged_records'],
                            'output_dir': str(dest),
                        }
                        event(db, key, run_id, batch_id, status, result)
                        results.append(result)
                        shutil.rmtree(stage)
                        continue

                    if dest.exists():
                        os.replace(
                            dest,
                            root / 'quarantine' / f'corrupt-{key}-{uuid4().hex}',
                        )

                    started = utcnow()
                    m = {
                        'processing_key': key,
                        'source_id': src['source_id'],
                        'file_sha256': sha,
                        'config_hash': cfg_hash,
                        'extractor_version': extractor_version,
                        'origin_filename': path.name,
                        'source_location': location,
                        'file_size': size,
                        'batch_id': batch_id,
                        'run_id': run_id,
                        'started_at': started,
                    }

                    with db:
                        db.execute(
                            '''INSERT OR REPLACE INTO processing
                            (processing_key,source_id,file_sha256,config_hash,
                             extractor_version,status,started_at,origin_filename,
                             source_location,file_size,batch_id,run_id)
                            VALUES(?,?,?,?,?,'PROCESSING',?,?,?,?,?,?)''',
                            (
                                key,
                                src['source_id'],
                                sha,
                                cfg_hash,
                                extractor_version,
                                started,
                                path.name,
                                location,
                                size,
                                batch_id,
                                run_id,
                            ),
                        )

                    extraction = extract(readable, src)
                    if not extraction.records:
                        raise ExtractionError('No extracted records')

                    for record in extraction.records:
                        record.update(
                            record_id=digest([
                                key,
                                record['table_id'],
                                record['source_record_locator'],
                            ]),
                            source_id=src['source_id'],
                            source_file_name=path.name,
                            source_location=location,
                            source_file_sha256=sha,
                            processing_key=key,
                            batch_id=batch_id,
                            run_id=run_id,
                            ingested_at_utc=started,
                            extractor_version=extractor_version,
                            config_hash=cfg_hash,
                        )

                    # Drop the temporary reader copy; retain the exact original.
                    readable.unlink()
                    m['ended_at'] = utcnow()

                    manifest = build_output(
                        stage,
                        extraction.records,
                        {**extraction.metadata, 'extraction_config': src},
                        extraction.checks,
                        m,
                    )

                    if fault:
                        fault('before_publish')

                    dest.parent.mkdir(exist_ok=True)
                    os.replace(stage, dest)
                    fsync_dir(dest.parent)

                    if fault:
                        fault('after_publish')

                    if not verify_output(dest, key):
                        raise ExtractionError(
                            'Published output failed integrity verification'
                        )

                    commit_state(db, manifest, dest)

                    result = {
                        'source_id': src['source_id'],
                        'file': path.name,
                        'status': 'PROCESSED',
                        'processing_key': key,
                        'row_count': manifest['row_count'],
                        'flagged_records': manifest['flagged_records'],
                        'output_dir': str(dest),
                    }
                    event(db, key, run_id, batch_id, 'PROCESSED', result)
                    results.append(result)

                except Exception as exc:
                    failed = {
                        'source_id': src['source_id'],
                        'file': path.name,
                        'processing_key': key,
                        'status': 'FAILED',
                        'error': f'{type(exc).__name__}: {exc}',
                    }

                    if stage.exists():
                        write_json(stage / 'failure.json', failed)
                        q = root / 'quarantine' / f'failed-{stage.name}'
                        os.replace(stage, q)
                        failed['quarantine_dir'] = str(q)

                    with db:
                        if key:
                            db.execute(
                                """UPDATE processing
                                SET status='FAILED',error=?,ended_at=?
                                WHERE processing_key=?""",
                                (failed['error'], utcnow(), key),
                            )

                    event(db, key, run_id, batch_id, 'FAILED', failed)
                    results.append(failed)

        summary = {
            'run_id': run_id,
            'batch_id': batch_id,
            'ended_at_utc': utcnow(),
            'results': results,
            'counts': {
                status: sum(r['status'] == status for r in results)
                for status in [
                    'PROCESSED',
                    'SKIPPED',
                    'RECOVERED',
                    'FAILED',
                    'MISSING',
                    'DEFERRED',
                ]
            },
            'flagged_records': sum(
                r.get('flagged_records', 0) for r in results
            ),
        }

        write_json(root / 'audit' / f'{run_id}.json', summary)
        return summary


def commit_state(db, m, dest):
    with db:
        db.execute(
            '''INSERT OR REPLACE INTO processing
            (processing_key,source_id,file_sha256,config_hash,extractor_version,
             status,output_dir,row_count,started_at,ended_at,origin_filename,
             source_location,file_size,batch_id,run_id)
            VALUES(?,?,?,?,?,'SUCCESS',?,?,?,?,?,?,?,?,?)''',
            (
                m['processing_key'],
                m['source_id'],
                m['file_sha256'],
                m['config_hash'],
                m['extractor_version'],
                str(dest),
                m['row_count'],
                m['started_at'],
                m['ended_at'],
                m['origin_filename'],
                m['source_location'],
                m['file_size'],
                m['batch_id'],
                m['run_id'],
            ),
        )