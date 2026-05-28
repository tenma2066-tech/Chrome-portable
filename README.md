# Chrome Portable (Policy Bypass Fork)

このリポジトリは、組織のグループポリシー (GPO) による制限を回避して起動することを目的とした、ポータブルな Google Chrome の独立フォークです。

## ダウンロード (一括)
最新版の ZIP パッケージは以下からダウンロードできます。
- **[Chrome-portable-v1.1.4.zip (GitHub Releases)](https://github.com/tenma2066-tech/Chrome-portable/releases/download/v1.1.4/Chrome-portable-v1.1.4.zip)**

## 重要事項
- **更新禁止**: Chrome 本体の更新は行わないでください（ポリシーバイパスが効かなくなる可能性があります）。
- **独立性**: PC のレジストリを恒久的に汚染することなく、ポータブルに起動可能です。

## 起動方法

環境に合わせて以下の 2 系統の起動方法を選択してください。追加の環境構築（Python 等）は不要です。

### 1. 管理者権限がある場合 (`Run.bat`)
最も推奨される方法です。
- `Run.bat` を実行してください。
- 自動的に管理者権限を要求し、ポリシーに関連するレジストリキーを DACL でロックして、強制インストール拡張機能などを完全に無効化した状態で Chrome を起動します。

### 2. 管理者権限がない場合 (`patch.bat`)
Python 等のインストールは不要です。Windows 標準機能のみで動作します。
- `patch.bat` を実行してください。
- 内部的に PowerShell (`patch.ps1`) を呼び出し、`App/Chrome-bin/*/chrome.dll` の内部文字列を書き換えることで制限を回避します。
- パッチ適用後、自動的に Chrome が起動します。

## 復元方法
レジストリのロックなどを解除し、元の組織ポリシーを適用したい場合は、以下のファイルを使用してください。
- `Restore.bat` / `Restore.ps1`

## ファイル構成
- `Run.bat` / `Run.ps1`: 管理者権限向けランチャー
- `patch.bat` / `patch.ps1`: 非管理者権限向けパッチ適用 & 起動スクリプト
- `GoogleChromePortable.exe`: ポータブル版ランチャー本体
- `App/`: Chrome 本体および DLL 類
- `Data/`: ユーザープロファイルデータ
