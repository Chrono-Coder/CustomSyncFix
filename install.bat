@echo off
echo Creating CustomSyncFix.zip...
powershell -Command "Compress-Archive -Path '%~dp042' -DestinationPath '%~dp0CustomSyncFix.zip' -Force"
echo.
echo Done! CustomSyncFix.zip created.
echo Extract it to: %%USERPROFILE%%\Zomboid\mods\
pause
