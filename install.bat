@echo off
echo Installing CustomSyncFix...
xcopy /E /I /Y "%~dp042" "%USERPROFILE%\Zomboid\mods\CustomSyncFix\42"
echo.
echo Done! CustomSyncFix installed to %USERPROFILE%\Zomboid\mods\CustomSyncFix
echo You can now join the server.
pause
