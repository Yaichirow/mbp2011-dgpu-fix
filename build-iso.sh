#!/bin/bash
# =============================================================================
# MacBook Pro 2011 dGPU Fix - ISO Builder v4 (macOS用)
# =============================================================================
# 動作環境 : macOS (Intel/Apple Silicon)
# 必要なもの: brew install xorriso
# 使い方   : bash build-iso.sh ubuntu-22.04.x-desktop-amd64.iso
# =============================================================================

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "使い方: bash $0 <ubuntu-22.04.x-desktop-amd64.iso>"
    exit 1
fi

INPUT_ISO="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_ISO="$(pwd)/custom-mbp2011.iso"
WORK_DIR="$(pwd)/iso-work"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
die()  { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; exit 1; }

# =============================================================================
# STEP 0: 環境チェック
# =============================================================================
clear
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║  MacBook Pro 2011 dGPU Fix - ISO Builder v4         ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""

command -v xorriso &>/dev/null \
    || die "xorriso が見つかりません: brew install xorriso"
ok "xorriso: $(xorriso --version 2>&1 | head -1)"
[[ -f "$INPUT_ISO" ]] || die "ISO が見つかりません: ${INPUT_ISO}"
ok "入力ISO: ${INPUT_ISO} ($(du -sh "$INPUT_ISO" | cut -f1))"

[[ -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
echo ""

# =============================================================================
# STEP 1: grub.cfg を取り出す
# =============================================================================
info "STEP 1/4: grub.cfg を取り出し中..."

GRUB_CFG_ORIG="${WORK_DIR}/grub.cfg.orig"
GRUB_CFG_MOD="${WORK_DIR}/grub.cfg"

xorriso -osirrox on \
        -indev "${INPUT_ISO}" \
        -extract /boot/grub/grub.cfg "${GRUB_CFG_ORIG}" \
        -- 2>/dev/null \
    || die "grub.cfg の取り出しに失敗"

ok "grub.cfg 取り出し完了"
echo ""

# =============================================================================
# STEP 2: grub.cfg を生成
#   - 先頭に dGPU Fix 専用エントリを追加
#   - set default=0 / set timeout=30 で自動選択
#   - init=/cdrom/dgpu-fix/run.sh でスクリプトを直接 PID1 として実行
# =============================================================================
info "STEP 2/4: grub.cfg を生成中..."

cat > "$GRUB_CFG_MOD" << 'GRUB_HEADER'
set default=0
set timeout=30

loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "MBP2011 dGPU Fix - NVRAM書き込み (自動選択)" {
    set gfxpayload=text
    linux  /casper/vmlinuz file=/cdrom/preseed/ubuntu.seed maybe-ubiquity quiet radeon.modeset=0 i915.modeset=1 i915.lvds_channel_mode=2 init=/cdrom/dgpu-fix/run.sh ---
    initrd /casper/initrd
}

GRUB_HEADER

# 元のエントリを追記（オリジナルの起動オプションも残す）
grep -v "^set timeout=" "$GRUB_CFG_ORIG" >> "$GRUB_CFG_MOD"

ok "grub.cfg 生成完了"
echo ""
echo "  先頭10行確認:"
head -10 "$GRUB_CFG_MOD" | sed 's/^/    /'
echo ""

# =============================================================================
# STEP 3: NVRAM書き込みスクリプトを作成
# =============================================================================
info "STEP 3/4: NVRAM書き込みスクリプトを作成中..."

SCRIPT_FILE="${WORK_DIR}/dgpu-fix-run.sh"

cat > "$SCRIPT_FILE" << 'ENDOFSCRIPT'
#!/bin/bash
# MacBook Pro 17" Late 2011 - dGPU Disable Tool
# init= で PID1 として起動される

# 基本 fs をマウント
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true

exec > /dev/console 2>&1
clear

echo ""
echo "  +----------------------------------------------------------+"
echo "  |  MacBook Pro 17-inch Late 2011  dGPU Disable Tool       |"
echo "  |  AMD Radeon HD 6750M -> OFF  /  Intel HD 3000 -> ON     |"
echo "  +----------------------------------------------------------+"
echo ""
echo "  [$(date '+%H:%M:%S')] 起動しました"

GUID="fa4ce28d-b62f-4c99-9cc3-6815686e30f9"
VAR_NAME="gpu-power-prefs"
EFIVAR_PATH="/sys/firmware/efi/efivars/${VAR_NAME}-${GUID}"

# EFI チェック
if [[ ! -d /sys/firmware/efi ]]; then
    echo "  [ERROR] EFIブートではありません"
    echo "  Option キーを押しながら電源 → EFI Boot を選択してください"
    sleep 30; reboot -f
fi
echo "  [OK] EFI 環境確認"

# efivarfs 確認
if ! mountpoint -q /sys/firmware/efi/efivars 2>/dev/null; then
    mount -t efivarfs efivarfs /sys/firmware/efi/efivars \
        || { echo "  [ERROR] efivarfs マウント失敗"; sleep 30; reboot -f; }
fi
echo "  [OK] efivarfs マウント確認"

# NVRAM 書き込み
if [[ -f "$EFIVAR_PATH" ]]; then
    chattr -i "$EFIVAR_PATH" 2>/dev/null || true
    CURRENT_HEX=$(xxd -p "$EFIVAR_PATH" 2>/dev/null | tr -d '\n' || echo "")
    CURRENT_VAL="${CURRENT_HEX:8:8}"
    echo "  [..] 現在の値: 0x${CURRENT_VAL}"
    if [[ "$CURRENT_VAL" == "01000000" ]]; then
        echo "  [OK] 既に設定済みです (dGPU無効化済み)"
    else
        python3 -c "import sys,struct; sys.stdout.buffer.write(struct.pack('<I',7)+struct.pack('<I',1))" \
            > "$EFIVAR_PATH" \
            && echo "  [OK] NVRAM 書き込み完了 (gpu-power-prefs = 0x01000000)" \
            || { echo "  [ERROR] 書き込み失敗"; sleep 30; reboot -f; }
    fi
else
    echo "  [..] 変数なし。新規作成します"
    python3 -c "import sys,struct; sys.stdout.buffer.write(struct.pack('<I',7)+struct.pack('<I',1))" \
        > "$EFIVAR_PATH" \
        && echo "  [OK] NVRAM 書き込み完了 (gpu-power-prefs = 0x01000000)" \
        || { echo "  [ERROR] 書き込み失敗"; sleep 30; reboot -f; }
fi

echo ""
echo "  +------------------------------------------+"
echo "  |  完了。次のステップ:                      |"
echo "  |  1. USB を抜く                            |"
echo "  |  2. 電源を入れ直す                        |"
echo "  |  3. 内蔵の macOS で起動する               |"
echo "  +------------------------------------------+"
echo ""

for i in 10 9 8 7 6 5 4 3 2 1; do
    printf "  再起動まで %2d 秒...\r" "$i"
    sleep 1
done
echo ""
reboot -f
ENDOFSCRIPT

chmod 755 "$SCRIPT_FILE"
ok "スクリプト作成完了"
echo ""

# =============================================================================
# STEP 4: ISO 生成
# =============================================================================
info "STEP 4/4: ISO を生成中 (数分かかります)..."

xorriso \
    -indev  "${INPUT_ISO}" \
    -outdev "${OUTPUT_ISO}" \
    -volid  "MBP2011-DGPU-FIX" \
    -map    "${GRUB_CFG_MOD}"  /boot/grub/grub.cfg \
    -map    "${SCRIPT_FILE}"   /dgpu-fix/run.sh \
    -boot_image any replay \
    -compliance no_emul_toc \
    -padding included \
    -- \
    2>&1 | grep -v "^$" \
         | grep -E "xorriso|Replayed|Writing|sectors|FAIL|ERROR|WARNING|Added" \
         | tail -15

ok "ISO 生成完了: ${OUTPUT_ISO} ($(du -sh "${OUTPUT_ISO}" | cut -f1))"

rm -rf "$WORK_DIR"

echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║  完了！                                              ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo "  生成ファイル: ${OUTPUT_ISO}"
echo ""
echo "  ─── USB 作成 ──────────────────────────────────────────"
echo "  balenaEtcher で custom-mbp2011.iso を USB に書き込む"
echo ""
echo "  ─── MacBook Pro での使い方 ────────────────────────────"
echo "  1. USB を挿して Option キーを押しながら電源"
echo "  2. 黄色い「EFI Boot」を選択"
echo "  3. GRUB メニューの最初の項目が自動選択される (30秒)"
echo "     「MBP2011 dGPU Fix - NVRAM書き込み」"
echo "  4. 黒い画面に [OK] NVRAM 書き込み完了 が出れば成功"
echo "  5. 自動再起動 → USB を抜いて macOS で起動"
echo ""
