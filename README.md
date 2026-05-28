# Chrome Portable (Policy Bypass Fork)

[日本語版は英語の後にあります / Japanese version follows the English text]

This repository provides a portable Google Chrome fork specifically configured to bypass organization-enforced Group Policy Objects (GPO). It allows you to run Chrome without being restricted by forced extensions (like monitoring software) or restricted settings.

## 📥 Download (Full Package)
You can download the latest pre-configured ZIP package from the link below:
- **[Chrome-portable-v1.1.4.zip (GitHub Releases)](https://github.com/tenma2066-tech/Chrome-portable/releases/download/v1.1.4/Chrome-portable-v1.1.4.zip)**

---

## 🇺🇸 English Guide

### ⚠️ Critical Information
- **DO NOT UPDATE**: Never update Chrome via the "About Google Chrome" menu. Updating will overwrite the patched files and re-enable organization restrictions.
- **PORTABILITY**: This version stores all data (history, bookmarks, passwords) in the `Data/` folder. It does not touch your system registry permanently.
- **EXTRACTION**: You **MUST** extract (unzip) the downloaded file completely before running. Running directly from inside a ZIP folder will cause errors.

### 🚀 How to Use (Two Methods)

Choose the method that fits your current environment (whether you have admin rights/password or not).

#### Method A: With Administrator Rights (`Run.bat`)
This is the most powerful method. It uses Registry DACL locking to block GPO from ever being applied to Chrome.
1. Double-click **`Run.bat`**.
2. Click **"Yes"** when the User Account Control (UAC) prompt appears.
3. A black console window will appear. It will delete organization policy keys, recreate them as empty, and lock them so the system cannot overwrite them.
4. Chrome will launch automatically. Organization extensions will be gone.

#### Method B: Without Administrator Rights (`patch.bat`)
Use this on school or work PCs where you don't have the admin password. No Python or extra software is required.
1. Double-click **`patch.bat`**.
2. A black console window will appear. It will search for `chrome.dll` and modify its internal logic to ignore "Google\Chrome" policy paths.
3. **Wait for a few seconds.** Since `chrome.dll` is large (~240MB), it takes time to apply the patch.
4. Once you see `[+] Patch applied successfully`, Chrome will launch automatically.
   * *Note: Subsequent launches will be instant as the patch is already applied.*

#### 🛠️ How to Revert
To remove the locks and restore original organization policies, run **`Restore.bat`** as an administrator.

---

## 🇯🇵 日本語ガイド

このリポジトリは、組織のグループポリシー（GPO）による制限を回避して起動することを目的とした、ポータブルな Google Chrome の独立フォークです。監視用拡張機能や設定制限を受けずに Chrome を使用できます。

### ⚠️ 重要事項（必ずお読みください）
- **更新禁止**: 設定画面の「Google Chrome について」等からアップデートを**絶対に行わないでください**。パッチが上書きされ、制限が復活します。
- **独立性**: 履歴・ブックマーク・パスワード等のデータはすべて `Data/` フォルダ内に保存されます。PC 本体のレジストリを恒久的に汚染しません。
- **解凍必須**: ダウンロードした ZIP ファイルは、右クリックから**「すべて展開」**して使用してください。ZIP の中から直接実行するとエラーになります。

### 🚀 起動方法（使いかた）

パソコンの環境（管理者パスワードを知っているかどうか）に合わせて、以下のいずれかを選択してください。

#### 【方法 A】 管理者権限が使える場合 (`Run.bat`)
最も確実で強力な方法です。レジストリを「ロック」して、組織の設定が書き込まれるのを物理的に遮断します。
1. **`Run.bat`** をダブルクリックして実行します。
2. 「ユーザーアカウント制御」が出たら **「はい」** を押してください。
3. 黒い画面（コンソール）が出て、ポリシーキーを削除・空で作成・DACL ロック（書き込み禁止化）を行います。
4. 数秒後に Chrome が起動します。強制拡張機能が消えているはずです。

#### 【【方法 B】 管理者権限がない場合 (`patch.bat`)
学校や会社の PC でパスワードが分からない場合でも使える方法です。Python などの追加ソフトは一切不要です。
1. **`patch.bat`** をダブルクリックして実行します。
2. 黒い画面が出ます。内部で `chrome.dll` を探索し、ポリシー参照パス（Google\Chrome）を無効なパスへ書き換えます。
3. **数秒〜数十秒待ってください。** `chrome.dll` は巨大（約240MB）なため、書き換えに時間がかかります。
4. `[+] Patch applied successfully` と表示されれば完了です。自動的に Chrome が起動します。
   * *※2回目以降はパッチ済みなので即座に起動します。*

#### 🛠️ 元に戻す方法
レジストリのロックを解除し、元の組織ポリシー（制限ありの状態）に戻したい場合は、**`Restore.bat`** を管理者として実行してください。

---

## 📁 File Structure / ファイル構成

- **`Run.bat` / `Run.ps1`**: Launcher for Admins. Locks registry keys. (管理者用。レジストリを保護)
- **`patch.bat` / `patch.ps1`**: Launcher for Non-Admins. Patches DLL file. (非管理者用。DLLを書き換え)
- **`GoogleChromePortable.exe`**: The portable launcher shell. (ポータブル版の起動用シェル)
- **`App/`**: Contains the Chrome program and DLLs. (Chrome プログラム本体)
- **`Data/`**: Your profile, history, and passwords. (あなたのユーザーデータ)
- **`Restore.bat` / `Restore.ps1`**: Scripts to revert all changes. (設定を元に戻す用)
