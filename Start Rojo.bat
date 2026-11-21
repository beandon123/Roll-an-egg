@echo off
rem Double-click to start the Rojo server for Roll an Egg, then press Connect in Studio's Rojo plugin.
rem Leave this window open while you work; closing it stops the sync.
title Rojo - Roll an Egg
cd /d "%~dp0"
echo Starting Rojo for Roll an Egg...
echo In Studio, press Connect in the Rojo plugin. Close this window to stop syncing.
echo.
rojo serve
echo.
echo Rojo stopped. If you see an error above, show it to Claude.
pause
