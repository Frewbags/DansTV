"""Inventory an official Samsung T-NKMUABC firmware ZIP without unpacking or flashing.

Usage: python scripts/tiz0wn/firmware-inventory.py PATH_TO_T-NKMUABC.zip
       python scripts/tiz0wn/firmware-inventory.py PATH_TO_T-NKMUABC.zip --sha256

This is a read-only OFFLINE helper. It does not download firmware, alter the
archive, decrypt/sign it, contact a TV or attempt to apply an exploit.
"""
import argparse
import hashlib
from pathlib import Path
import zipfile

EXPECTED_NAME = "T-NKMUABC.zip"
MAX_PRINT = 80


def check(path: Path, calc_hash: bool, check_contents: bool) -> int:
    if not path.is_file():
        raise ValueError(f"Firmware ZIP not found: {path}")
    if path.name.upper() != EXPECTED_NAME.upper():
        raise ValueError(
            f"Expected {EXPECTED_NAME}; got {path.name}. "
            "Never use a different firmware family or substitute a Q90T image."
        )
    print(f"File: {path}")
    print(f"Archive bytes: {path.stat().st_size:,}")
    if calc_hash:
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        print(f"SHA-256: {digest.hexdigest()}")
    try:
        with zipfile.ZipFile(path) as archive:
            if check_contents and archive.testzip() is not None:
                raise ValueError("ZIP contains a damaged member")
            members = archive.infolist()
            if not members:
                raise ValueError("ZIP has no entries")
            total = sum(m.file_size for m in members)
            print(f"Members: {len(members)}; uncompressed bytes: {total:,}")
            for member in members[:MAX_PRINT]:
                print(f"  {member.file_size:>14,}  {member.filename}")
            if len(members) > MAX_PRINT:
                print(f"  ... and {len(members) - MAX_PRINT} more members")
            family_match = any("T-NKMUABC" in m.filename.upper() for m in members)
            print(f"Internal filenames contain T-NKMUABC: {family_match}")
            print("This is an archive inventory, not a firmware/build identity or signature verification.")
    except zipfile.BadZipFile as exc:
        raise ValueError("Not a valid ZIP archive") from exc
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", type=Path, help="Official T-NKMUABC.zip already downloaded to this PC")
    parser.add_argument("--sha256", action="store_true", help="Compute full local file digest")
    parser.add_argument("--check-contents", action="store_true", help="Decompress and CRC-check every member (slow for large ZIPs)")
    args = parser.parse_args()
    try:
        return check(args.zip, args.sha256, args.check_contents)
    except (ValueError, OSError) as exc:
        parser.exit(2, f"{exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
