@echo off
REM Doble clic aqui. Trae un menu para elegir el modo y las opciones, asi que no
REM hay que abrir PowerShell ni acordarse de ninguna flag.
REM
REM Si esta Puente.exe al lado lo usa a el; si no, corre puente.ps1 con
REM -ExecutionPolicy Bypass, que aplica solo a ese proceso y no cambia nada del PC.

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

REM Valores por defecto: teclear, con Enter final, en mayusculas.
set "MODO=real"
set "SIN_ENTER="
set "MINUSCULAS="

:menu
cls
echo.
echo   ================================================
echo     PUENTE NFC   -   lector ACR122U como teclado
echo   ================================================
echo.
if "%MODO%"=="real" (
    echo     [1]  Modo .......... TECLEAR el UID en la ventana activa
) else (
    echo     [1]  Modo .......... PRUEBA, solo lo muestra en pantalla
)
if defined SIN_ENTER (
    echo     [2]  Enter final ... NO
) else (
    echo     [2]  Enter final ... SI
)
if defined MINUSCULAS (
    echo     [3]  Formato ....... minusculas    ^(04a1b2c3^)
) else (
    echo     [3]  Formato ....... MAYUSCULAS    ^(04A1B2C3^)
)
echo.
echo     [I]  Iniciar el puente
echo     [S]  Salir
echo.
echo   Pulsa un numero para cambiar esa opcion.
echo.

set "op="
set /p "op=Opcion: "

if /i "%op%"=="1" goto cambiar_modo
if /i "%op%"=="2" goto cambiar_enter
if /i "%op%"=="3" goto cambiar_formato
if /i "%op%"=="i" goto iniciar
if /i "%op%"=="s" exit /b 0
goto menu

:cambiar_modo
if "%MODO%"=="real" (set "MODO=prueba") else (set "MODO=real")
goto menu

:cambiar_enter
if defined SIN_ENTER (set "SIN_ENTER=") else (set "SIN_ENTER=1")
goto menu

:cambiar_formato
if defined MINUSCULAS (set "MINUSCULAS=") else (set "MINUSCULAS=1")
goto menu

:iniciar
REM Cada opcion del menu se traduce a la flag que espera el script.
set "ARGS="
if "%MODO%"=="prueba" set "ARGS=%ARGS% -SinTeclear"
if defined SIN_ENTER set "ARGS=%ARGS% -SinEnter"
if defined MINUSCULAS set "ARGS=%ARGS% -Minusculas"

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
