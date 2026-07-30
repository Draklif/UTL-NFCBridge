@echo off
REM Doble clic aqui para arrancar el puente sin tener que abrir PowerShell.
REM -ExecutionPolicy Bypass aplica solo a este proceso: no cambia nada del PC.
setlocal
title Puente NFC
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0puente.ps1" %*
echo.
echo El puente se detuvo. Pulsa una tecla para cerrar esta ventana.
pause >nul
