<#
    Empaqueta puente.ps1 como Puente.exe.

    Esto es opcional: Puente.bat ya se abre con doble clic y no necesita
    construirse. El .exe sirve si quieres repartir un solo archivo suelto, sin
    el .ps1 al lado.

    Correr una vez en tu PC (no en el de los estudiantes):
        powershell -NoProfile -ExecutionPolicy Bypass -File construir-exe.ps1

    Avisos:
      - El .exe sigue siendo el mismo script adentro, no se compila nada. No es
        mas rapido ni mas seguro que el .ps1.
      - Los antivirus desconfian de los ejecutables hechos con ps2exe, porque
        tambien los usa el malware para esconder scripts. Si Defender lo borra,
        no pelees con el: reparte Puente.bat, que nunca da ese problema.
#>

$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Instalando ps2exe (solo para tu usuario, sin administrador)..."
    Install-Module ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe

$origen  = Join-Path $PSScriptRoot "puente.ps1"
$destino = Join-Path $PSScriptRoot "Puente.exe"

Invoke-ps2exe -inputFile $origen -outputFile $destino `
    -title "Puente NFC" `
    -description "Lee el UID de una tarjeta NFC y lo teclea en la ventana activa" `
    -noConsole:$false

Write-Host ""
Write-Host "Listo: $destino"
Write-Host "Para el modo de prueba:  .\Puente.exe -SinTeclear"
