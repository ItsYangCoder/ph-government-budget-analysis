"""Package an inspected local execution snapshot with code and audit evidence."""
import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from pondolens.output import verify_output


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--runtime',required=True)
    p.add_argument('--zip',required=True)
    args=p.parse_args()
    project=Path(__file__).resolve().parents[1]
    runtime=Path(args.runtime).resolve()
    docs=project/'docs';docs.mkdir(exist_ok=True)
    testing=subprocess.run([sys.executable,'-m','pytest','-q'],cwd=project,text=True,capture_output=True)
    (docs/'pytest_results.txt').write_text(testing.stdout+testing.stderr)
    if testing.returncode:
        raise SystemExit('Tests failed; delivery not packaged')
    revisions=[]
    for path in sorted((runtime/'committed').glob('*/*')):
        m=json.loads((path/'manifest.json').read_text())
        if not verify_output(path,m['processing_key']):
            raise SystemExit(f'Output integrity failure: {path.name}')
        revisions.append({'source_id':m['source_id'],'processing_key':m['processing_key'],
                          'source_file_name':m['origin_filename'],'file_sha256':m['file_sha256'],
                          'row_count':m['row_count'],'flagged_records':m['flagged_records'],
                          'validation':'verified','output':f"run_artifacts/committed/{m['source_id']}/{m['processing_key']}"})
    runs=[json.loads(f.read_text()) for f in (runtime/'audit').glob('*.json')]
    selected={label:next(r for r in runs if r['batch_id']==label) for label in
              ['initial-final','extensions-final','rerun-final','full-idempotency-verification']}
    report={'tests':testing.stdout.strip(),'sources':revisions,
            'total_records':sum(r['row_count'] for r in revisions),
            'source_processing_keys':len(revisions),
            'first_run_processed':selected['initial-final']['counts']['PROCESSED']+selected['extensions-final']['counts']['PROCESSED'],
            'rerun_skipped':selected['rerun-final']['counts']['SKIPPED']+selected['full-idempotency-verification']['counts']['SKIPPED'],
            'rerun_new_outputs':selected['rerun-final']['counts']['PROCESSED']+selected['full-idempotency-verification']['counts']['PROCESSED'],
            'failed_final_sources':selected['initial-final']['counts']['FAILED']+selected['extensions-final']['counts']['FAILED'],
            'remote_databricks_execution':'not tested / no remote writes',
            'agency_scope':'summary sheets only; detail/SUCs deferred'}
    (docs/'audit_summary.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['# Execution report','',testing.stdout.strip(),'',
           f"First final run: {report['first_run_processed']} processing keys committed. Rerun: {report['rerun_skipped']} skipped, {report['rerun_new_outputs']} new outputs.",
           f"Total retained source measures/physical cells: {report['total_records']}. Final source failures: {report['failed_final_sources']}.",'',
           '| Source | Records | SHA-256 |','|---|---:|---|']
    for r in revisions:lines.append(f"| {r['source_id']} | {r['row_count']} | `{r['file_sha256']}` |")
    lines += ['', 'All original/output digests, Parquet row counts and manifests verified before packaging.',
              'All records retain declared source interpretation flags. Successful extraction does not resolve geographic or financial comparability.',
              'Databricks helper syntax compiled locally but no Spark/Delta workspace run was performed.',
              'Agency extraction is limited to summary sheets. Additional indicators/PSGC are deferred.',
              '', 'During development, merged-cell handling failed and was fixed with a regression test. A subsequent clean final run processed both agency summaries successfully.',
              'Ledger persistence was hardened using SQLite rollback-journal mode under the local writer lock; cross-process reruns are tested.',
              '', 'Machine-readable detail: audit_summary.json. Run-level evidence: run_artifacts/audit/.']
    (docs/'execution_report.md').write_text('\n'.join(lines)+'\n')
    snapshot=project/'run_artifacts'
    snapshot.mkdir(exist_ok=True)
    for name in ['committed','audit']:
        shutil.copytree(runtime/name,snapshot/name,dirs_exist_ok=True)
    # Use SQLite backup rather than copying a live ledger file.
    with sqlite3.connect(runtime/'state.sqlite') as source,sqlite3.connect(snapshot/'state.sqlite') as target:
        source.backup(target)
    out=Path(args.zip);out.parent.mkdir(parents=True,exist_ok=True)
    with ZipFile(out,'w',compression=ZIP_DEFLATED,compresslevel=6) as z:
        for f in sorted(project.rglob('*')):
            if not f.is_file() or any(part in {'__pycache__','.pytest_cache','.venv'} or part.endswith('.egg-info') for part in f.relative_to(project).parts):
                continue
            z.write(f,str(Path(project.name)/f.relative_to(project)))
    with out.open('rb') as archive:
        os.fsync(archive.fileno())
    fd=os.open(out.parent,os.O_RDONLY)
    try:os.fsync(fd)
    finally:os.close(fd)
    with ZipFile(out) as z:
        assert z.testzip() is None
        assert any(n.endswith('/README.md') for n in z.namelist())
        print(json.dumps({'zip':str(out),'size_bytes':out.stat().st_size,
                          'file_count':len(z.namelist()),'report':report},indent=2))


if __name__=='__main__':main()
