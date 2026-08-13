# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

[[ -f /etc/cicada/live-banner.txt ]] && cat /etc/cicada/live-banner.txt

~/.automated_script.sh
