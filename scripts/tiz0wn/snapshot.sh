#!/bin/sh
# Read-only resource and debloat baseline for a Tizen 5.5 TV.
# Run using an already validated root command channel. Redirect output to a PRIVATE PC file.
set -u
printf '=== Timestamp / platform ===\n'
date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || :
uname -a 2>/dev/null || :
cat /etc/tizen-release 2>/dev/null || :
cat /etc/info.ini 2>/dev/null | head -25 || :
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
printf '\n=== End of snapshot ===\n'
