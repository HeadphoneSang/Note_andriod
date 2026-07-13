@echo off
set PATH=d:\flutter\bin;d:\flutter\bin\cache\dart-sdk\bin;%PATH%
cd /d d:\pro\note_project\note_for_android
flutter build apk --debug
if %ERRORLEVEL% NEQ 0 (
    echo Build failed with error code %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)
echo Build successful!
pause
