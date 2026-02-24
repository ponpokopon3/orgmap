@echo off
set DRIVE_LETTER=Q:
set FOLDER_PATH=%~dp0
set PORT=8080

echo --- ネットワークドライブ(Q:)の準備 ---
:: 既存のQドライブがあれば一旦解除
if exist %DRIVE_LETTER% subst %DRIVE_LETTER% /d
:: このバッチがあるフォルダをQドライブとしてマウント
subst %DRIVE_LETTER% "%FOLDER_PATH:~0,-1%"

echo --- サーバー起動中 (http://localhost:%PORT%) ---
echo ※このウィンドウを閉じると終了します
echo.

:: ブラウザで自動的にページを開く
:: start http://localhost:%PORT%/index.html

:: PowerShellスクリプトを呼び出してサーバーを起動（ポート競合時はフォールバック）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -StartPort %PORT% -Drive %DRIVE_LETTER%
pause