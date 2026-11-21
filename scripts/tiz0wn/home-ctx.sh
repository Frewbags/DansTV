#!/bin/sh
# DansTV Tizen 5.5 Home-key trial; adapted from tiz0wn's tvctx-manager investigation.
# MIT credit: https://github.com/sebastianspicker/tiz0wn
# Run ON the owned TV via an already validated root command channel. Not an SDB command.
# Usage: sh home-ctx.sh status APP_ID | backup APP_ID | apply APP_ID | restore APP_ID
set -eu

mode=${1:-}
app=${2:-}
case "$mode" in status|backup|apply|restore) ;; *) echo "usage: $0 status|backup|apply|restore APP_ID" >&2; exit 2 ;; esac
case "$app" in ""|*[!A-Za-z0-9._-]*) echo "invalid app id" >&2; exit 2 ;; esac
printf '%s\n' "$app" | grep -Eq '^[A-Za-z0-9]{10}\.[A-Za-z0-9_-]{1,52}$' || { echo "expected a Samsung SDK app id" >&2; exit 2; }

DB=/opt/dbspace/.app-context.db
ROOT=/opt/usr/share/danstv-home
SAVE="$ROOT/home-original.db"
META="$ROOT/home-app-id"
ORIGINAL=package:com.samsung.tv.csfs
TARGET=package:"$app"
WHERE="appid='com.samsung.tv.csfs' AND key='XF86Home' AND request='launch'"
sqlite() { sqlite3 -readonly -noheader -separator '|' "$DB" "$1"; }
row() { sqlite "SELECT target_selector,args FROM key_filter WHERE $WHERE;"; }
count() { sqlite "SELECT count(*) FROM key_filter WHERE $WHERE;"; }
managed() { sqlite "SELECT appid,ui_type,source FROM managed_app WHERE appid='$app';"; }
fail() { printf 'DansTV Home: %s\n' "$1" >&2; exit 65; }
need_root() { [ "$(id -u)" = 0 ] || fail 'requires verified root access, not ordinary SDB'; }
need_db() {
    command -v sqlite3 >/dev/null 2>&1 || fail 'sqlite3 is unavailable'
    [ -f "$DB" ] || fail 'app-context database not found'
    [ "$(count)" = 1 ] || fail 'expected exactly one Samsung Home key row'
}
need_record() {
    [ -f "$SAVE" ] && [ -f "$META" ] || fail 'baseline missing; never reconstruct it from the applied DB'
    [ "$(cat "$META")" = "$app" ] || fail 'backup belongs to another app id'
    [ "$(sqlite3 -readonly -noheader -separator '|' "$SAVE" "SELECT target_selector,args FROM key_filter WHERE $WHERE;")" = "$ORIGINAL|entry_point:smarthub_key" ] ||
        fail 'saved original does not contain expected stock Home row'
}
reload() {
    command -v vconftool >/dev/null 2>&1 || fail 'cannot reload tvctx-manager'
    old=$(vconftool get memory/appfw/app_context_db_change 2>/dev/null | sed -n 's/.*value = \([0-9][0-9]*\).*/\1/p')
    case "$old" in ''|*[!0-9]*) fail 'cannot read tvctx-manager reload counter' ;; esac
    new=$((old + 1))
    vconftool set -t int memory/appfw/app_context_db_change "$new" -f >/dev/null 2>&1 ||
        vconftool set -t int memory/appfw/app_context_db_change "$new" >/dev/null 2>&1 ||
        fail 'home row changed, but tvctx-manager reload failed; use status/restore'
    printf 'tvctx-manager reload %s -> %s\n' "$old" "$new"
}
need_root
need_db
case "$mode" in
    status)
        printf 'Samsung XF86Home row: %s\n' "$(row)"
        printf 'DansTV managed row: %s\n' "$(managed)"
        if [ -f "$SAVE" ]; then
            printf 'Baseline SHA256: '; sha256sum "$SAVE"
        else
            printf 'Baseline: absent\n'
        fi
        exit 0
        ;;
    backup)
        [ "$(row)" = "$ORIGINAL|entry_point:smarthub_key" ] || fail 'not at the original Home value'
        [ -z "$(managed)" ] || fail 'launcher already has a managed row'
        # Fail closed if an older baseline is present; never overwrite a working rollback.
        [ ! -e "$SAVE" ] && [ ! -e "$META" ] || fail 'baseline already exists'
        umask 077
        mkdir -p "$ROOT"
        sqlite3 "$DB" ".backup '$SAVE'" || fail 'database backup failed'
        [ "$(sqlite3 -readonly -noheader -separator '|' "$SAVE" "SELECT target_selector,args FROM key_filter WHERE $WHERE;")" = "$ORIGINAL|entry_point:smarthub_key" ] ||
            fail 'backup did not verify'
        printf '%s\n' "$app" >"$META"
        sha256sum "$SAVE"
        printf 'Backup created; copy %s and %s privately OFF the TV before apply.\n' "$SAVE" "$META"
        ;;
    apply)
        [ "${DANSTV_HOME_WRITE_CONFIRM:-}" = 'I_HAVE_OFF_TV_BACKUP' ] || fail 'set DANSTV_HOME_WRITE_CONFIRM=I_HAVE_OFF_TV_BACKUP explicitly'
        need_record
        [ "$(row)" = "$ORIGINAL|entry_point:smarthub_key" ] || fail 'original Home value has changed'
        [ -z "$(managed)" ] || fail 'managed row already exists; refusing to modify it'
        [ "$(sqlite "SELECT count(*) FROM managed_app WHERE appid='com.samsung.tv.searchall';")" = 1 ] ||
            fail 'reference full-screen managed app missing; do not guess ui_type'
        # Do not tamper with other Home/longpress rules. Single transaction.
        sqlite3 "$DB" "BEGIN IMMEDIATE;
          INSERT INTO managed_app(appid,ui_type,source)
            SELECT '$app',ui_type,source FROM managed_app WHERE appid='com.samsung.tv.searchall';
          UPDATE key_filter SET target_selector='$TARGET'
            WHERE $WHERE AND target_selector='$ORIGINAL' AND args='entry_point:smarthub_key';
          COMMIT;" || fail 'transaction failed; check status immediately'
        [ "$(row)" = "$TARGET|entry_point:smarthub_key" ] || fail 'readback mismatch; run restore'
        reload
        printf 'Home trial applied. Press Home to check; then run restore before reboot.\n'
        ;;
    restore)
        need_record
        current=$(row)
        if [ "$current" = "$ORIGINAL|entry_point:smarthub_key" ] && [ -z "$(managed)" ]; then
            printf 'Already restored.\n'
            exit 0
        fi
        [ "$current" = "$TARGET|entry_point:smarthub_key" ] || fail 'unexpected Home row; manual reconciliation required'
        [ "$(sqlite "SELECT count(*) FROM managed_app WHERE appid='$app';")" = 1 ] ||
            fail 'expected managed row missing; manual reconciliation required'
        sqlite3 "$DB" "BEGIN IMMEDIATE;
          UPDATE key_filter SET target_selector='$ORIGINAL'
            WHERE $WHERE AND target_selector='$TARGET' AND args='entry_point:smarthub_key';
          DELETE FROM managed_app WHERE appid='$app';
          COMMIT;" || fail 'restore transaction failed'
        [ "$(row)" = "$ORIGINAL|entry_point:smarthub_key" ] && [ -z "$(managed)" ] ||
            fail 'restore did not verify'
        reload
        printf 'Samsung Home route restored. Baseline files retained.\n'
        ;;
esac
