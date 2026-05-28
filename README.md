# Chrome Portable (Policy Bypass Fork)

[日本語版は英語の後にあります / Japanese version follows the English text]

This is a specialized, independent fork of **Google Chrome Portable** designed to bypass organization-enforced Group Policy Objects (GPO). It allows users to browse without restrictive policies, forced extensions (monitoring software), or blocked settings, all while remaining completely portable.

## 📥 Download (Full Package)
Download the latest pre-configured package from the link below:
- **[Chrome-portable-v1.1.4.zip (GitHub Releases)](https://github.com/tenma2066-tech/Chrome-portable/releases/download/v1.1.4/Chrome-portable-v1.1.4.zip)**

---

## 🇺🇸 English Guide

### 📂 Understanding Portability & Extraction
Unlike a standard installation, this version is **fully isolated**. 
- **Data Isolation**: All your history, saved passwords, and extensions are stored within the `Data/` folder inside the app directory. No data is stored in the host computer's `%AppData%`.
- **Zero-Footprint Execution**: It does not require installation. You can run it from a USB drive or a personal folder.
- **CRITICAL - Extraction Required**: You **MUST NOT** run the files from within the ZIP folder. Windows Explorer allows you to see inside a ZIP, but the application cannot write to it. 
  1. Right-click the downloaded ZIP.
  2. Select **"Extract All..."**.
  3. Run the scripts from the resulting unzipped folder.

### ⚙️ The Mechanics of Bypass
Organizations typically use GPO to enforce settings by writing to specific Registry keys. This fork offers two ways to stay independent:

#### Method A: Administrator Bypass (`Run.bat`)
*Requires Admin Privileges. Recommended for personal PCs or where you have the password.*
- **How it works**: It uses Windows DACL (Distributed Access Control List) to "lock" the registry keys that Chrome reads for policies. It deletes existing policies, creates empty keys, and tells Windows to **DENY** anyone (including the system) from writing to them again.
- **Benefit**: 100% effective against GPO refreshes. Even if the school/company tries to push a new policy, Windows will block the write attempt.

#### Method B: Binary Patching Bypass (`patch.bat`)
*No Admin Privileges needed. Use this on restricted School/Work PCs.*
- **How it works**: It performs a binary search-and-replace on `chrome.dll` (the heart of Chrome). It changes the hardcoded registry paths that Chrome looks for (e.g., `SOFTWARE\Policies\Google\Chrome` becomes an invalid string).
- **Benefit**: Since Chrome can no longer "find" the location where the organization stores its restrictions, it starts in a "Clean" state as if it were a fresh, unmanaged install.

### 🚀 Usage Instructions
1. **Extract** the ZIP file to a folder.
2. **Close** any existing instances of Chrome.
3. Run **`Run.bat`** (if you have admin) or **`patch.bat`** (if you don't).
4. **Never Update**: If you see an "Update available" prompt, ignore it. Updating will overwrite the patched `chrome.dll` and restore restrictions.

### 🛠️ Restoration & Safety
To revert Method A's registry locks, run **`Restore.bat`** as an administrator. This will delete the locks and allow the organization's policies to be re-applied normally.

---

## 🇯🇵 日本語ガイド

このリポジトリは、組織（学校・企業等）のグループポリシー (GPO) による制限を回避するために特別に構成された **Google Chrome Portable** の独立フォークです。監視用拡張機能の強制導入や、設定のロックを受けずに、自由なブラウジング環境をポータブルに持ち運ぶことができます。

### 📂 ポータブル環境と「展開」について
通常の Chrome と異なり、このバージョンは **「完全隔離」** されています。
- **データの隔離**: 閲覧履歴、保存したパスワード、拡張機能などのデータはすべて、フォルダ内の `Data/` フォルダに保存されます。パソコン本体の `%AppData%` には一切データを残しません。
- **足跡を残さない**: インストール不要で、USB メモリや個人用フォルダから直接実行できます。
- **【重要】必ず「展開」してください**: 
  ダウンロードした ZIP ファイルをダブルクリックして中身が見えた状態で実行するのは**間違い**です。その状態ではファイルの書き込みができないため、必ず以下の手順を踏んでください。
  1. ダウンロードした ZIP を右クリック。
  2. **「すべて展開...」** を選択。
  3. 展開（解凍）された後のフォルダ内にあるスクリプトを実行。

### ⚙️ 制限回避の仕組み（テクニカル解説）
通常、組織はレジストリという Windows の設定領域にデータを書き込むことで Chrome を制限します。このフォークでは、2 つのアプローチでこれを無効化します。

#### 【方法 A】 管理者権限によるバイパス (`Run.bat`)
*管理者パスワードを知っている場合に推奨。*
- **仕組み**: Windows の DACL（アクセス制御リスト）を利用して、レジストリキーを物理的に **「ロック」** します。既存の制限を削除して空のキーを作り、システム（SYSTEM権限）であっても二度と書き込めないように拒否設定を行います。
- **利点**: 非常に強力です。組織が「ポリシーの強制更新」をかけても、Windows 自体が書き込みを拒否するため、制限が復活しません。

#### 【方法 B】 バイナリパッチによるバイパス (`patch.bat`)
*管理者権限が一切ない場合に。学校の PC などで有効。*
- **仕組み**: Chrome の心臓部である `chrome.dll` をバイナリレベルで検索し、制限情報を見に行くパス（住所）を書き換えます（例: `Google\Chrome` という文字列を無効なものに変える）。
- **利点**: Chrome 自体が「制限がどこに書いてあるか」を見失うため、あたかも管理されていない個人の PC で起動したかのように、クリーンな状態で立ち上がります。

### 🚀 詳細な使いかた
1. ZIP ファイルを**展開**します。
2. すでに開いている Chrome があればすべて**閉じます**。
3. **`Run.bat`** (管理者あり) または **`patch.bat`** (管理者なし) を実行します。
4. **絶対に更新しない**: Chrome のメニューからアップデートを行うと、パッチ済みの DLL が上書きされ、制限が復活してしまいます。

### 🛠️ 復元と安全性
方法 A で行ったレジストリのロックを解除し、元の組織環境に戻したい場合は、**`Restore.bat`** を管理者として実行してください。これによりロックが解除され、通常のポリシーが再適用されるようになります。

---

## 📁 File Structure / ファイル構成
- `Run.bat / Run.ps1`: Primary launcher for Admins. (管理者用メインランチャー)
- `patch.bat / patch.ps1`: Binary patcher for Non-Admins. (非管理者用パッチ実行)
- `Restore.bat / Restore.ps1`: Reverts all system changes. (システムを元の状態に戻す)
- `GoogleChromePortable.exe`: Original portable shell. (ポータブル版の基本シェル)
- `App/`: Chrome binaries and DLLs. (プログラム本体)
- `Data/`: User profile and data storage. (プロファイル・データ保存先)

---

## ⚖️ Disclaimer
This tool is for educational and personal research purposes only. Use it responsibly and in accordance with your organization's acceptable use policy. The author is not responsible for any data loss or policy violations.
本ツールは教育および個人研究の目的で提供されています。組織の利用規約を遵守し、自己責任で使用してください。
