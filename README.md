# MacBook Pro 17” Late 2011 dGPU Disable Tool

MacBook Pro 17インチ Late 2011 (MacBookPro8,3) の AMD Radeon HD 6750M (dGPU) 故障による画面異常を回避するツールです。

EFI NVRAM に `gpu-power-prefs = 0x01000000` を書き込み、Intel HD 3000 (iGPU) での起動を強制します。

## 必要なもの

- 作業用 Mac (macOS が動いていれば機種不問)
- [Homebrew](https://brew.sh/)
- Ubuntu 22.04 LTS Desktop ISO
- USB メモリ (8GB 以上)
- [balenaEtcher](https://etcher.balena.io/)

## 使い方

### 1. xorriso をインストール

```bash
brew install xorriso
```

### 2. Ubuntu 22.04 Desktop ISO をダウンロード

https://releases.ubuntu.com/22.04/

ファイル名: `ubuntu-22.04.x-desktop-amd64.iso`

### 3. カスタム ISO を生成

`build-iso.sh` と Ubuntu の ISO を同じフォルダに置いて実行します。

```bash
bash build-iso.sh ubuntu-22.04.x-desktop-amd64.iso
```

約5〜10分で `custom-mbp2011.iso` が生成されます。空き容量は10GB以上必要です。

### 4. USB に書き込む

balenaEtcher で `custom-mbp2011.iso` を USB メモリに書き込みます。

### 5. MacBook Pro で実行

1. USB を MacBook Pro 17” Late 2011 に挿す
1. **Option キーを押しながら電源ボタン**
1. 起動選択画面で黄色い **「EFI Boot」** を選択
1. GRUB メニューで **「MBP2011 dGPU Fix - NVRAM書き込み」** が自動選択される (30秒待つか Enter)
1. 黒い画面に `[OK] NVRAM 書き込み完了` が表示されれば成功
1. 自動で再起動するので **USB を抜いて** 内蔵の macOS で起動する

## 仕組み

|項目      |内容                                       |
|--------|-----------------------------------------|
|NVRAM 変数|`gpu-power-prefs`                        |
|GUID    |`fa4ce28d-b62f-4c99-9cc3-6815686e30f9`   |
|書き込む値   |`0x01000000`                             |
|効果      |dGPU (AMD) を無効化し iGPU (Intel HD 3000) で起動|
|永続性     |NVRAM に書き込まれるため電池が切れない限り保持               |

カーネルパラメータ `radeon.modeset=0 i915.modeset=1 i915.lvds_channel_mode=2` により、dGPU が故障していても Linux が起動できます。スクリプトは `init=` で PID 1 として直接実行されるため、Ubuntu のデスクトップ環境は起動しません。

## 元に戻す方法

macOS の Terminal から:

```bash
sudo nvram -d fa4ce28d-b62f-4c99-9cc3-6815686e30f9:gpu-power-prefs
```

## 対象機種

MacBook Pro 17-inch Late 2011 (MacBookPro8,3)

他の2011年モデル (MacBookPro8,1 / 8,2) でも同じ NVRAM 変数が使われていますが、動作確認は MacBookPro8,3 のみです。

## ライセンス

MIT License

このスクリプト自体は MIT License です。
`build-iso.sh` が生成する ISO には Ubuntu が含まれます。Ubuntu は Canonical Ltd. の商標であり、GPL 等の各種オープンソースライセンスの下で配布されています。詳細は [Ubuntu のライセンス情報](https://ubuntu.com/legal/intellectual-property-policy) を参照してください。