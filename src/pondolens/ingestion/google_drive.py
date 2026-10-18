"""ingestion.google_drive responsibilities for one ingestion run."""
import io
import json
from pathlib import Path
from pondolens.common.config import FOLDER_MIME, SHEET_MIME, XLSX_MIME
import pondolens.ingestion.google_drive as ingestion_google_drive

def list_children(drive, folder_id):
    token = None
    while True:
        response = drive.files().list(q=f"'{folder_id}' in parents and trashed = false", pageSize=1000, pageToken=token, fields='nextPageToken,files(id,name,mimeType,modifiedTime,size)', supportsAllDrives=True, includeItemsFromAllDrives=True).execute(num_retries=3)
        yield from response.get('files', [])
        token = response.get('nextPageToken')
        if not token:
            break

def walk(drive, folder_id, prefix='', visited=None):
    visited = set() if visited is None else visited
    if folder_id in visited:
        raise ValueError('Repeated folder in traversal')
    visited.add(folder_id)
    for item in sorted(ingestion_google_drive.list_children(drive, folder_id), key=lambda x: x['name']):
        relative = prefix + item['name']
        if item['mimeType'] == FOLDER_MIME:
            yield from ingestion_google_drive.walk(drive, item['id'], relative + '/', visited)
        else:
            yield {**item, 'relative_path': relative}

def download(ctx, drive, item):
    if item['mimeType'] == SHEET_MIME:
        request = drive.files().export_media(fileId=item['id'], mimeType=XLSX_MIME)
    else:
        request = drive.files().get_media(fileId=item['id'], supportsAllDrives=True)
    limit = ctx.PARAMS['max_file_mb'] * 1024 * 1024
    if item.get('size') and int(item['size']) > limit:
        raise ValueError(f"File exceeds max_file_mb: {item['relative_path']}")
    buffer = io.BytesIO()
    downloader = ctx.MediaIoBaseDownload(buffer, request, chunksize=1024 * 1024)
    done = False
    while not done:
        _, done = downloader.next_chunk(num_retries=3)
        if buffer.tell() > limit:
            raise ValueError(f"Download exceeds max_file_mb: {item['relative_path']}")
    after = drive.files().get(fileId=item['id'], fields='modifiedTime', supportsAllDrives=True).execute(num_retries=3)
    if after['modifiedTime'] != item['modifiedTime']:
        raise RuntimeError(f"File changed during download: {item['relative_path']}")
    return buffer.getvalue()

def load_credentials(ctx):
    """Use an existing secret or an explicitly selected credentials file."""
    if ctx.PARAMS['auth_mode'] == 'secret':
        try:
            raw = ctx.dbutils.secrets.get(scope=ctx.SECRET_SCOPE, key=ctx.SECRET_KEY)
        except Exception:
            raise RuntimeError('Cannot read service-account secret. Verify secret_scope, secret_key and READ access, or select auth_mode=file with service_account_path.') from None
    else:
        credential_path = Path(ctx.PARAMS['service_account_path'])
        if not credential_path.is_absolute() or not credential_path.is_file():
            raise ValueError('service_account_path must point to an existing absolute JSON file path')
        raw = credential_path.read_text(encoding='utf-8-sig')
    try:
        info = json.loads(raw)
    except (ValueError, TypeError):
        raise ValueError('Credentials must contain valid service-account JSON') from None
    required = ('client_email', 'private_key', 'token_uri')
    if not isinstance(info, dict) or info.get('type') != 'service_account' or (not all((isinstance(info.get(key), str) and info[key].strip() for key in required))):
        raise ValueError('Credentials must be a service-account JSON with client_email, private_key and token_uri')
    try:
        return ctx.service_account.Credentials.from_service_account_info(info, scopes=['https://www.googleapis.com/auth/drive.readonly'])
    except Exception:
        raise ValueError('Cannot initialize service-account credentials; check the JSON key file') from None
