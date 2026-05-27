import os
import sys
import traceback
import subprocess
import glob

def kill_chrome_processes():
    """chrome.dll への書き込みロックを回避するため、実行中の Chrome プロセスを終了させる"""
    print("[*] 競合回避のため、既存の Chrome プロセスを終了します...")
    try:
        subprocess.run(
            ["taskkill", "/F", "/IM", "chrome.exe", "/T"], 
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL
        )
    except Exception:
        pass

def main():
    try:
        # 1. 既存プロセスの終了
        kill_chrome_processes()

        # 2. 実行ディレクトリの取得
        base_dir = os.path.dirname(os.path.abspath(__file__))
        
        # 3. chrome.dll の探索
        search_pattern = os.path.join(base_dir, "App", "Chrome-bin", "*", "chrome.dll")
        dll_paths = glob.glob(search_pattern)

        if not dll_paths:
            print(f"[ERROR] chrome.dll が見つかりません。")
            print(f"探索パス: {search_pattern}")
            return

        # 置換対象の定義 (UTF-16LE 文字列として置換)
        patch_targets = [
            ("SOFTWARE\\Policies\\Google\\Chrome", "SOFTWARE\\Policies\\Xoogle\\Xhrome"),
            ("SOFTWARE\\Policies\\Google\\Update", "SOFTWARE\\Policies\\Xoogle\\Uxdate")
        ]

        # 4. パッチ適用
        for target_dll in dll_paths:
            print(f"\n[*] ターゲット: {target_dll}")
            
            with open(target_dll, 'rb') as f:
                file_data = f.read()

            is_modified = False

            for target, dummy in patch_targets:
                target_bytes = target.encode('utf-16-le')
                dummy_bytes = dummy.encode('utf-16-le')
                
                target_count = file_data.count(target_bytes)
                dummy_count = file_data.count(dummy_bytes)
                
                if target_count > 0:
                    print(f"  [+] '{target}' を {target_count} 箇所発見。パッチを適用します。")
                    file_data = file_data.replace(target_bytes, dummy_bytes)
                    is_modified = True
                elif dummy_count > 0:
                    print(f"  [i] 既に '{dummy}' へパッチ適用済みです。")
                else:
                    print(f"  [-] '{target}' が見つかりません。")

            if is_modified:
                print("  [*] 変更を保存中...")
                with open(target_dll, 'wb') as f:
                    f.write(file_data)
                print("  [+] パッチ適用完了。")
            else:
                print("  [i] 変更の必要はありません。")

        print("\n[+] すべての処理が完了しました。")

        # 5. Chrome の起動
        launcher_candidates = [
            os.path.join(base_dir, "GoogleChromePortable.exe"),
            os.path.join(base_dir, "App", "Chrome-bin", "chrome.exe"),
        ]
        for launcher in launcher_candidates:
            if os.path.exists(launcher):
                print(f"[*] 起動します: {launcher}")
                subprocess.Popen([launcher], cwd=base_dir)
                break
        else:
            print("[WARN] 起動可能な実行ファイルが見つかりません。")

    except Exception:
        print("\n[FATAL ERROR] 処理中にエラーが発生しました:")
        print(traceback.format_exc())

if __name__ == "__main__":
    main()
    print("\n" + "-"*40)
    input("Enter キーを押して終了してください...")
