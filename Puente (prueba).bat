@echo off
REM Igual que Puente.bat pero sin teclear: solo muestra los UID en pantalla.
REM Sirve para comprobar que el lector funciona antes de culpar a la app.
setlocal
title Puente NFC (prueba)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0puente.ps1" -SinTeclear
echo.
echo El puente se detuvo. Pulsa una tecla para cerrar esta ventana.
pause >nul
