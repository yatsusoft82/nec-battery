# NEC VersaPro Battery Charge Control for Linux

NEC VersaPro ノートPCのバッテリー充電開始・終了しきい値を、LinuxからACPI経由で設定・確認するためのコマンドラインスクリプトです。

> **重要:** このスクリプトは、特定のNEC VersaProで確認したACPIメソッドを直接呼び出します。すべてのNEC VersaProで動作することを保証するものではありません。対応していることを確認できていない機種では使用しないでください。

## Features

- 充電開始しきい値の設定
- 充電終了しきい値の設定
- 現在の充電開始・終了しきい値の読み出し
- 現在のバッテリー残量（%）の表示
- 現在の充電状態（充電中、充電停止、放電中など）の表示
- TLPのバッテリーしきい値機能に依存しない
- `acpi-call` を利用してNEC固有のACPIメソッドを呼び出す

## Tested environment

| 項目 | 確認環境 |
|---|---|
| PC | NEC VersaPro |
| Product Name | `PC-VEE11R5GL5LM` |
| Family | `VersaPro` |
| BIOS | `/924A2000` |
| EC Firmware | `1.7` |
| Battery | `BAT1` |
| Battery model | `PC-VP-BP144` |
| OS | Ubuntu 26.04.1 LTS |
| Kernel | `7.0.0-31-generic` |
| Secure Boot | Enabled |
| acpi-call-dkms | 1.2.2-2.1build1 |

## Requirements / Ubuntu 26.04 setup

このスクリプトは、Ubuntu 26.04.1 LTSの標準的なバッテリーsysfsだけでは動作しません。`/proc/acpi/call` を提供する `acpi-call` カーネルモジュールが必要です。

### 1. `acpi-call-dkms` をAPTでインストール

まずパッケージ情報を更新します。

```bash
sudo apt update
```

次に `acpi-call-dkms` をインストールします。

```bash
sudo apt install acpi-call-dkms
```

`acpi-call-dkms` は、LinuxからACPIメソッドを呼び出すためのカーネルモジュールをDKMSで構築・管理するUbuntuパッケージです。

このパッケージを入れると、必要な `dkms` などの依存パッケージもAPTが解決してインストールします。したがって、通常は `dkms` を別途インストールする必要はありません。

インストール確認：

```bash
dpkg -l acpi-call-dkms dkms
```

### 2. `acpi_call` モジュールをロード

パッケージをインストールしただけでは、モジュールが現在のセッションでロードされていない場合があります。

```bash
sudo modprobe acpi_call
```

確認：

```bash
lsmod | grep acpi_call
```

さらに、スクリプトが利用するインターフェースを確認します。

```bash
ls -l /proc/acpi/call
```

`/proc/acpi/call` が存在すれば準備完了です。

### 3. Secure Bootを有効にしている場合

Secure Bootが有効な環境では、DKMSで構築された外部カーネルモジュールの署名が必要になることがあります。

例えば、

```bash
sudo modprobe acpi_call
```

で、

```text
Key was rejected by service
```

と表示される場合、Secure Bootによってモジュールが拒否されている可能性があります。

この場合は、Ubuntu/DKMSが提示するMOK（Machine Owner Key）の登録手順に従ってください。MOK登録はSecure Bootの設定に関係するため、環境によって画面や手順が異なります。

登録済みMOKの確認には `mokutil` を使用できます。必要ならAPTで導入します。

```bash
sudo apt install mokutil
mokutil --list-enrolled
```

このプロジェクトのテスト環境では、Secure Bootを有効にした状態で `acpi_call` モジュールをロードして使用できることを確認しています。

### 必要なAPTパッケージまとめ

最小限、このスクリプトの実行に必要なのは次のパッケージです。

```bash
sudo apt update
sudo apt install acpi-call-dkms
```

Secure BootでMOKの状態を確認したい場合は、追加で：

```bash
sudo apt install mokutil
```

`mokutil` はスクリプトそのものの動作には必須ではありません。

## Installation

リポジトリを取得した後、スクリプトを実行可能にします。

```bash
chmod +x nec-battery.sh
```

`/usr/local/bin` に `nec-battery` というコマンドとしてインストールする場合：

```bash
sudo install -m 755 nec-battery.sh /usr/local/bin/nec-battery
```

以後は、どのディレクトリからでも次のように実行できます。

```bash
sudo nec-battery status
```

## Usage

### 現在の設定と充電状態を表示

```bash
sudo nec-battery
```

または：

```bash
sudo nec-battery status
```

出力例：

```text
=== NEC VersaPro バッテリー設定 ===
充電開始     : 75%
充電終了     : 80%

=== 現在の充電状態 ===
現在の充電量 : 85%
充電状態     : 充電停止
```

### 充電開始・終了しきい値を設定

例えば、

```bash
sudo nec-battery 80 85
```

とすると、80%で充電開始、85%で充電終了となるように設定します。

元の確認済み設定に戻す場合：

```bash
sudo nec-battery 75 80
```

開始値と終了値には0～99の整数を指定できます。通常は `開始 < 終了` としてください。

## How it works

対象機種で確認したACPIパス：

```text
\\_SB_.PC00.LPCB.EC0_.HKEY
```

使用するメソッド：

| メソッド | 動作 |
|---|---|
| `BCTG` | 充電開始値を取得 |
| `BCCS` | 充電開始値を設定 |
| `BCSG` | 充電終了値を取得 |
| `BCSS` | 充電終了値を設定 |

例えば：

```text
\\_SB_.PC00.LPCB.EC0_.HKEY.BCCS 80
\\_SB_.PC00.LPCB.EC0_.HKEY.BCSS 85
```

を `/proc/acpi/call` 経由で呼び出します。

## ACPI implementation details

確認したDSDTでは、EC RAM上の以下のフィールドが使われています。

```text
STOC = ERAM offset 0xE7
STRC = ERAM offset 0xE8
```

`BCTG` / `BCCS` は `STRC`、`BCSG` / `BCSS` は `STOC` を読み書きします。

本スクリプトは `/dev/mem` に直接書き込む方式ではありません。対象機種のACPIメソッドを経由してEC側の値を変更します。

## Why not TLP?

テスト環境ではTLPのバッテリーしきい値機能が利用できず、

```text
Supported features: none available
```

となりました。また標準的な、

```text
charge_control_start_threshold
charge_control_end_threshold
```

も利用できませんでした。

そのため、TLPではなくNEC固有のACPIメソッドを使用しています。

## Important safety notes

このスクリプトはバッテリーの充電制御値をファームウェア/EC側へ書き込みます。

- 対応機種以外では使用しないでください。
- ACPIメソッドは機種ごとに異なる可能性があります。
- `BCCS` / `BCSS` に渡す値は、このプロジェクトで確認した範囲では0～99です。
- スクリプトは通常の使用範囲として `開始 < 終了` を要求します。
- 使用によって発生したデータ損失、ハードウェア障害、バッテリーへの影響などについて保証しません。
- 別機種でACPIパスやメソッド名を推測して実行しないでください。

## Verification

Windows環境で設定されていた、

```text
充電開始: 75%
充電終了: 80%
```

をLinuxから読み出せることを確認しました。

その後、

```text
充電開始: 80%
充電終了: 85%
```

へ変更し、実際に80%付近で充電を開始し、85%付近で充電が停止することを確認しました。

## Limitations

現時点では以下は未検証です。

- すべてのNEC VersaPro機種での互換性
- BIOS/ECファームウェアのすべてのバージョンでの動作
- Secure Boot設定が異なる環境での動作

## Contributing

別のNEC VersaProで動作確認できた場合は、PC型番、BIOS、EC、Ubuntu/Linux、Kernel、ACPIパス、ACPIメソッド、実際の充電開始・終了動作などを共有していただけると、対応機種情報の拡充に役立ちます。

## License

MIT License。詳細は [LICENSE](LICENSE) を参照してください。
