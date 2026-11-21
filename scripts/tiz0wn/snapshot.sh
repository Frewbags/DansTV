#!/bin/sh
# Read-only resource and debloat baseline for a Tizen 5.5 TV.
# Run using an already validated root command channel. Redirect output to a PRIVATE PC file.
set -u
printf '=== Timestamp / platform ===\n'
date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
uname -a 2>/dev/null || :
cat /etc/tizen-release 2>/dev/null || :
cat /etc/info.ini 2>/dev/null | head -25 || :
# Integration inventory is deliberately a *shell* survey, not evidence of
# the web-service Node runtime, a provisioned broker, or an enabled Home hook.
# Do not launch new processes as root merely to identify a runtime.
printf '\n=== Tizen 5.5 service prerequisites (read-only) ===\n'
printf 'Node executable in PATH: '
if command -v node >/dev/null 2>&1; then printf 'present\n'; else printf 'not observed\n'; fi
printf 'dotnet launcher executable: '
if [ -x /usr/bin/dotnet-launcher ]; then printf 'present\n'; else printf 'not observed\n'; fi
printf 'apps_rw data directory: '
if [ -d /opt/usr/home/owner/apps_rw ]; then printf 'present\n'; else printf 'not observed\n'; fi
printf 'Survey shell SMACK label: '
if [ -r /proc/self/attr/current ]; then
    cat /proc/self/attr/current 2>/dev/null || printf 'unreadable\n'
else
    printf 'not readable\n'
fi
printf 'Web-service Node version: not measured by this shell survey\n'
printf 'Broker ownership and authentication: not measured by this shell survey\n'
printf '\n=== Home / startup preference inventory (read-only) ===\n'
# Arn0/Q70B and CleanFrame/Frame reports use different Home interfaces.
# Record exact Q80T values before selecting a method; missing values are not defaults.
if command -v vconftool >/dev/null 2>&1; then
    for key in \
        db/appfw/home_appid \
        db/appfw/startup_appid \
        db/appfw/booting_appid_backup \
        db/first_screen/type \
        db/menu/smart_hub/ontvsetting/auto_start
    do
        printf '%s: ' "$key"
        if ! vconftool get "$key" 2>/dev/null; then
            printf '(not readable or absent)\n'
        fi
    done
else
    echo 'vconftool unavailable; no Home preference inference'
fi
if [ -r /etc/prd_info.ini ]; then
    grep '^Version=' /etc/prd_info.ini 2>/dev/null | head -1 || :
fi
printf 'Native main-operation handler: not measured by this shell survey\n'
# Do not write appfw preferences, registry tables or native operation selectors.
printf '\n=== Uptime / load / RAM (KiB) ===\n'
cat /proc/uptime /proc/loadavg 2>/dev/null || :
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null || :
printf '\n=== Overall CPU over one second ===\n'
cpu_sample() {
    awk '/^cpu / { total=0; for (i=2; i<=NF; i++) total+=$i; print total, $5+$6; exit }' /proc/stat
}
first=$(cpu_sample)
sleep 1
second=$(cpu_sample)
printf '%s\n%s\n' "$first" "$second" | awk '
    NR==1 { total=$1; idle=$2 }
    NR==2 { dt=$1-total; di=$2-idle; if (dt>0) printf "CPU busy: %.1f%% (all cores)\n",100*(dt-di)/dt; else print "CPU: no valid interval" }
'
printf '\n=== Process summary (may differ across firmware) ===\n'
ps -eo pid,ppid,rss,comm 2>/dev/null | head -65 || ps 2>/dev/null | head -65 || :
printf '\n=== Selected user-visible and background packages ===\n'
if command -v pkgcmd >/dev/null 2>&1; then
    pkgcmd -l 2>/dev/null | grep -Ei 'acr-service-app|multi-assistant|multiscreen|ScreenMirroring|nfc-monitor|waapp-contents|hbbtv|google-cal-sync|calendar-account|csfs|tv-viewer|Jellyfin|DansTV' | head -65 || :
else
    echo 'pkgcmd unavailable'
fi
printf '\n=== Home key context (read-only) ===\n'
if command -v sqlite3 >/dev/null 2>&1 && [ -r /opt/dbspace/.app-context.db ]; then
    sqlite3 -readonly -header /opt/dbspace/.app-context.db "SELECT appid,key,request,target_selector,args FROM key_filter WHERE key='XF86Home';" 2>/dev/null || :
else
    echo 'No readable app-context database'
fi
# Candidate inventory only: never stop, mask, restart or disable any unit.
# The service names below were observed on this specific Q80T/firmware.
printf '\n=== Telemetry candidate unit inventory (read-only) ===\n'
if command -v systemctl >/dev/null 2>&1; then
    for unit in \
        acr.service \
        adagent-service.service \
        canalysis-service.service \
        contents-recognition-service.service \
        media-analytics-service.service \
        vision-data-recognition-service.service \
        kpi-logging.service \
        issue_report_agent.service
    do
        printf '\nUNIT %s\n' "$unit"
        # State, resolved unit path and direct dependency edges; no service
        # contents, Environment, ExecStart or private command arguments.
        systemctl show "$unit" --no-pager \
            -p Id -p LoadState -p ActiveState -p SubState \
            -p UnitFileState -p MainPID -p FragmentPath \
            -p Requires -p Wants -p RequiredBy -p WantedBy \
            -p PartOf -p BindsTo -p Conflicts \
            2>/dev/null | head -17 || :
    done
else
    printf 'systemctl unavailable; no service dependency inference\n'
fi

# Socket observation is optional and deliberately excludes every endpoint,
# hostname, IP address and port. A single socket snapshot is NOT proof of
# upstream telemetry or absence of traffic. Child PIDs may be missed.
printf '\n=== Candidate network socket counts (read-only, no endpoints) ===\n'
if command -v ss >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    # One system snapshot, not eight changing separate observations.
    socket_status=measured
    socket_rows=$(ss -H -tunap 2>/dev/null) || socket_status=not_measured
    if [ "$socket_status" = not_measured ]; then
        printf 'ss could not inspect sockets; not measured\n'
    else
    for unit in \
        acr.service adagent-service.service canalysis-service.service \
        contents-recognition-service.service media-analytics-service.service \
        vision-data-recognition-service.service kpi-logging.service \
        issue_report_agent.service
    do
        pid=$(systemctl show "$unit" -p MainPID 2>/dev/null | sed -n 's/^MainPID=//p' | head -1)
        case "$pid" in
            ''|0|*[!0-9]*) printf '%s: main_pid_unavailable\n' "$unit";;
            *)
                count=$(printf '%s\n' "$socket_rows" | awk -v pid="$pid" '
                    index($0, "pid=" pid ",") || index($0, "pid=" pid ")") { n++ }
                    END { print n+0 }
                ')
                printf '%s: main_pid_socket_rows=%s (single snapshot; children not covered)\n' "$unit" "$count"
                ;;
        esac
    done
    fi
else
    printf 'ss or systemctl unavailable; network observation not measured\n'
fi

# Consistent SQLite backup of only the Home context database.
# Source is opened read-only. A private transient copy under /tmp is removed
# before this shell exits; nothing is written to the live Home database.
# The encoded backup stays inside the private one-use report; never commit it.
printf '\n=== Home DB verified backup export ===\n'
if command -v sqlite3 >/dev/null 2>&1 &&
   command -v mktemp >/dev/null 2>&1 &&
   command -v sha256sum >/dev/null 2>&1 &&
   command -v base64 >/dev/null 2>&1 &&
   [ -r /opt/dbspace/.app-context.db ]; then
    home_tmp=$(mktemp /tmp/.danstv-homedb-XXXXXXXX) || home_tmp=''
    if [ -n "$home_tmp" ]; then
        trap 'rm -f "$home_tmp"' EXIT HUP INT TERM
        if sqlite3 -readonly /opt/dbspace/.app-context.db ".backup '$home_tmp'" >/dev/null 2>&1; then
            home_check=$(sqlite3 -readonly "$home_tmp" 'PRAGMA quick_check;' 2>/dev/null) || home_check=''
            home_row=$(sqlite3 -readonly -separator '|' "$home_tmp" "SELECT target_selector,args FROM key_filter WHERE appid='com.samsung.tv.csfs' AND key='XF86Home' AND request='launch';" 2>/dev/null) || home_row=''
            home_size=$(wc -c < "$home_tmp" | tr -d '[:space:]')
            case "$home_size" in
                ''|*[!0-9]*) home_size=0 ;;
            esac
            if [ "$home_check" = ok ] &&
               [ "$home_row" = 'package:com.samsung.tv.csfs|entry_point:smarthub_key' ] &&
               [ "$home_size" -ge 1024 ] && [ "$home_size" -le 262144 ]; then
                home_hash=$(sha256sum "$home_tmp" | cut -d ' ' -f1)
                case "$home_hash" in
                    *[!0-9a-f]*|'') printf 'HOME-DB-UNAVAILABLE hash_failed\n' ;;
                    *)
                        printf 'HOME-DB-BEGIN sha256=%s bytes=%s\n' "$home_hash" "$home_size"
                        base64 "$home_tmp" || printf 'HOME-DB-ENCODING-FAILED\n'
                        printf 'HOME-DB-END\n'
                        ;;
                esac
            else
                printf 'HOME-DB-UNAVAILABLE integrity_or_original_row_mismatch\n'
            fi
        else
            printf 'HOME-DB-UNAVAILABLE sqlite_backup_failed\n'
        fi
        rm -f "$home_tmp"
        trap - EXIT HUP INT TERM
    else
        printf 'HOME-DB-UNAVAILABLE mktemp_failed\n'
    fi
else
    printf 'HOME-DB-UNAVAILABLE prerequisites_missing\n'
fi

printf '\n=== End of snapshot ===\n'
