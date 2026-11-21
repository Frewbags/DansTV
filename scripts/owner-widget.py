"""Prepare an owner-identified unsigned Tizen widget or inspect a signed widget.

No signing credentials, TV connection, or native Home changes are performed here.
"""
import argparse
from pathlib import Path
import zipfile

from font_assets import write_widget_archive
from local_config import ROOT, load_settings, manifest_identity
from private_files import check_signed_widget, check_widget

UPSTREAM_ID = manifest_identity((ROOT / 'app/config.xml').read_bytes())


def owner_identity():
    if not (ROOT / '.local/signing.json').is_file():
        raise ValueError('Create ignored .local/signing.json with your own SDK-generated identity first.')
    settings = load_settings()
    if settings['identity'] == UPSTREAM_ID:
        raise ValueError('Use your own SDK-generated package_id and app_id, not the reference maintainer identity.')
    return settings['identity']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='Validate private owner configuration without producing a widget.')
    parser.add_argument('--verify', metavar='SIGNED_WGT', type=Path, help='Validate a signed owner widget without installing it.')
    args = parser.parse_args()
    identity = owner_identity()
    if args.check:
        print('Owner identity configuration is valid: ' + identity['app_id'])
        return
    if args.verify:
        check_signed_widget(args.verify, identity)
        print('Signed widget structure, owner identity and private-file checks passed (not a cryptographic signature validation).')
        return
    output = ROOT / 'dist/DansTV-unsigned.wgt'
    output.parent.mkdir(exist_ok=True)
    write_widget_archive(output, root=ROOT, include_private=False, identity=identity)
    check_widget(output)
    with zipfile.ZipFile(output) as archive:
        if manifest_identity(archive.read('config.xml')) != identity:
            raise ValueError('Unsigned widget identity does not match owner configuration.')
    print('Unsigned owner widget prepared: ' + str(output))
    print('Application ID: ' + identity['app_id'])
    print('Sign with your own Samsung certificate profile before installing.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, zipfile.BadZipFile) as exc:
        raise SystemExit(str(exc) if isinstance(exc, ValueError) else 'Widget preparation or verification failed.') from None
