#!/bin/bash

# NEC VersaPro battery charge threshold utility
# BAT1 / HKEY.BCCS / HKEY.BCSS

ACPI_CALL="/proc/acpi/call"
HKEY='\_SB_.PC00.LPCB.EC0_.HKEY'

# Must be root
if [ "$EUID" -ne 0 ]; then
    echo "このスクリプトは sudo で実行してください。"
    echo "例: sudo $0 80 85"
    exit 1
fi

# acpi_call module / interface check
if [ ! -e "$ACPI_CALL" ]; then
    echo "/proc/acpi/call がありません。"
    echo "先に acpi_call モジュールを読み込んでください:"
    echo "  sudo modprobe acpi_call"
    exit 1
fi

# /proc/acpi/call can return a trailing NUL byte.
# Remove it before command substitution to avoid Bash warnings.
acpi_read() {
    cat "$ACPI_CALL" | tr -d '\0'
}

read_start() {
    local raw value
    printf '%s\n' "$HKEY.BCTG 0" > "$ACPI_CALL"
    raw=$(acpi_read)
    if [[ "$raw" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        value=$((16#${BASH_REMATCH[1]}))
        printf '%d' "$((value & 0xff))"
    else
        echo "取得失敗: $raw" >&2
        return 1
    fi
}

read_stop() {
    local raw value
    printf '%s\n' "$HKEY.BCSG 0" > "$ACPI_CALL"
    raw=$(acpi_read)
    if [[ "$raw" =~ ^0x([0-9a-fA-F]+)$ ]]; then
        value=$((16#${BASH_REMATCH[1]}))
        printf '%d' "$((value & 0xff))"
    else
        echo "取得失敗: $raw" >&2
        return 1
    fi
}

write_start() {
    local result
    printf '%s\n' "$HKEY.BCCS $1" > "$ACPI_CALL"
    result=$(acpi_read)
    [[ "$result" == "0x0" ]]
}

write_stop() {
    local result
    printf '%s\n' "$HKEY.BCSS $1" > "$ACPI_CALL"
    result=$(acpi_read)
    [[ "$result" == "0x0" ]]
}

show_status() {
    local capacity status
    capacity=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
    status=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null)

    if [ -z "$capacity" ] || [ -z "$status" ]; then
        echo "BAT1 の充電状態を取得できません。"
        return 1
    fi

    echo "現在の充電量 : ${capacity}%"
    case "$status" in
        Charging)
            echo "充電状態     : 充電中"
            ;;
        Discharging)
            echo "充電状態     : 放電中"
            ;;
        Full)
            echo "充電状態     : 充電完了"
            ;;
        "Not charging")
            echo "充電状態     : 充電停止"
            ;;
        *)
            echo "充電状態     : $status"
            ;;
    esac
}

show_all() {
    local start stop
    start=$(read_start) || return 1
    stop=$(read_stop) || return 1

    echo "=== NEC VersaPro バッテリー設定 ==="
    echo "充電開始     : ${start}%"
    echo "充電終了     : ${stop}%"
    echo
    echo "=== 現在の充電状態 ==="
    show_status
}

usage() {
    cat <<EOF
使い方:
  sudo $0                  現在の設定と充電状態を表示
  sudo $0 START STOP       充電開始/終了を設定して表示
  sudo $0 status           現在の設定と充電状態を表示

例:
  sudo $0 80 85
  sudo $0 75 80

START/STOP は 0～99 の整数。
通常は START < STOP にしてください。
EOF
}

# 引数なし: 表示
if [ "$#" -eq 0 ] || [ "$1" = "status" ]; then
    show_all
    exit $?
fi

# 設定: START STOP
if [ "$#" -ne 2 ]; then
    usage
    exit 1
fi

START="$1"
STOP="$2"

if ! [[ "$START" =~ ^[0-9]+$ ]] || ! [[ "$STOP" =~ ^[0-9]+$ ]]; then
    echo "開始・終了値は 0～99 の整数で指定してください。"
    exit 1
fi

if (( START < 0 || START > 99 || STOP < 0 || STOP > 99 )); then
    echo "開始・終了値は 0～99 の範囲で指定してください。"
    exit 1
fi

if (( START >= STOP )); then
    echo "通常は「開始 < 終了」としてください。"
    echo "例: sudo $0 80 85"
    exit 1
fi

echo "${START}% で充電開始、${STOP}% で充電終了に設定します。"

if ! write_start "$START"; then
    echo "充電開始値の書き込みに失敗しました。"
    exit 1
fi

if ! write_stop "$STOP"; then
    echo "充電終了値の書き込みに失敗しました。"
    exit 1
fi

echo "設定しました。"
echo
show_all
