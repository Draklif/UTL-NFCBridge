@echo off
REM Doble clic aqui para arrancar el puente sin abrir PowerShell a mano.
REM
REM Este .bat solo lanza puente.ps1; no toca en nada la lectura de tarjetas.
REM -ExecutionPolicy Bypass aplica solo a este proceso: no cambia nada del PC.
REM Si hay un Puente.exe al lado, usa ese en vez del .ps1.

setlocal
title Puente NFC
cd /d "%~dp0"

if exist "%~dp0Puente.exe" (
    set "MOTOR=%~dp0Puente.exe"
    set "LANZAR="%~dp0Puente.exe""
) else (
    set "MOTOR=%~dp0puente.ps1"
    set "LANZAR=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0puente.ps1""
)

if not exist "%MOTOR%" (
    echo No encuentro ni Puente.exe ni puente.ps1 en esta carpeta.
    echo Deja este .bat junto a uno de los dos.
    echo.
    pause
    exit /b 1
)

set "MODO=real"

:menu
cls
echo.
echo   ================================================
echo     PUENTE NFC   -   lector ACR122U como teclado
echo   ================================================
echo.
if "%MODO%"=="real" (
    echo     [1]  Modo .... TECLEAR el UID en la ventana activa
) else (
    echo     [1]  Modo .... PRUEBA, solo lo muestra en pantalla
)
echo.
echo     [I]  Iniciar el puente
echo     [S]  Salir
echo.
echo   Pulsa 1 para cambiar de modo.
echo.

set "op="
set /p "op=Opcion: "

if /i "%op%"=="1" goto cambiar_modo
if /i "%op%"=="i" goto iniciar
if /i "%op%"=="s" exit /b 0
goto menu

:cambiar_modo
if "%MODO%"=="real" (set "MODO=prueba") else (set "MODO=real")
goto menu

:iniciar
set "ARGS="
if "%MODO%"=="prueba" set "ARGS= -SinTeclear"

cls
if "%MODO%"=="real" (
    echo   Recuerda dejar ENFOCADA la ventana donde quieres que aparezca el UID.
    echo.
)
%LANZAR%%ARGS%

echo.
echo   El puente se detuvo.
pause
goto menu
