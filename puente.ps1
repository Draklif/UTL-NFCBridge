<#
    Puente ACR122U -> teclado, para usar un lector USB con la app desde un PC.

    El navegador de escritorio no expone lectores NFC a JavaScript: Web NFC solo
    existe en Chrome para Android. Muchas apps web resuelven esto aceptando la
    otra entrada, la de los lectores HID que "teclean" el UID y cierran con
    Enter. El ACR122U no es un teclado, es un lector PC/SC, asi que aqui lo
    traducimos: leemos el UID por PC/SC y lo escribimos como pulsaciones en la
    ventana activa.

    Para la app receptora es indistinguible de un lector HID, y por eso no hay
    que tocar nada de su lado: ni servidor, ni pagina, ni permisos del navegador.

    Va en PowerShell y no en Node a proposito: los bindings PC/SC de npm compilan
    binario nativo y exigen Visual Studio Build Tools, que en un PC prestado o
    institucional no se pueden instalar. winscard.dll ya esta en cualquier
    Windows. Sin dependencias, sin compilar, sin administrador.

    Uso:  .\puente.ps1              teclea el UID en la ventana activa
          .\puente.ps1 -SinTeclear  solo lo muestra en consola (para probar)
#>

param(
    [switch]$SinTeclear
)

$ErrorActionPreference = "Stop"

# Enlace con la API de tarjetas inteligentes de Windows. Es la misma que usa el
# sistema para los lectores de cedula y token bancarios.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class WinScard {
    [StructLayout(LayoutKind.Sequential)]
    public struct IO_REQUEST { public uint Protocol; public uint PciLength; }

    [DllImport("winscard.dll")]
    public static extern int SCardEstablishContext(uint scope, IntPtr r1, IntPtr r2, out IntPtr ctx);

    [DllImport("winscard.dll")]
    public static extern int SCardReleaseContext(IntPtr ctx);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode)]
    public static extern int SCardListReaders(IntPtr ctx, string groups, char[] readers, ref int len);

    [DllImport("winscard.dll", CharSet = CharSet.Unicode)]
    public static extern int SCardConnect(IntPtr ctx, string reader, uint share, uint protocols, out IntPtr card, out uint activeProtocol);

    [DllImport("winscard.dll")]
    public static extern int SCardDisconnect(IntPtr card, uint disposition);

    [DllImport("winscard.dll")]
    public static extern int SCardTransmit(IntPtr card, ref IO_REQUEST send, byte[] sendBuf, int sendLen, IntPtr recv, byte[] recvBuf, ref int recvLen);
}
"@

$SCARD_SCOPE_USER      = 0
$SCARD_SHARE_SHARED    = 2
$SCARD_PROTOCOL_T0T1   = 3
$SCARD_LEAVE_CARD      = 0
$SCARD_S_SUCCESS       = 0

$PAUSA_SONDEO_MS = 250  # cada cuanto se pregunta si hay tarjeta encima

# Cuantas vueltas seguidas sin tarjeta hacen falta para admitir una lectura
# nueva. Con la tarjeta quieta encima, el ACR122U falla de vez en cuando una
# vuelta suelta (devuelve SCARD_W_REMOVED_CARD y a la siguiente vuelve a
# responder); sin este margen ese parpadeo se cuenta como tarjeta retirada y la
# vuelve a leer. Tres vueltas son 750 ms: nadie retira y reapoya tan rapido.
$AUSENCIAS_PARA_REARMAR = 3

if (-not $SinTeclear) {
    Add-Type -AssemblyName System.Windows.Forms
}

# ── Contexto y lector ────────────────────────────────
$ctx = [IntPtr]::Zero
if ([WinScard]::SCardEstablishContext($SCARD_SCOPE_USER, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$ctx) -ne $SCARD_S_SUCCESS) {
    throw "No se pudo abrir el servicio de tarjetas inteligentes. Revisa que el servicio 'Smart Card' (SCardSvr) este corriendo."
}

# SCardListReaders devuelve varios nombres pegados y separados por nulos.
$len = 0
[void][WinScard]::SCardListReaders($ctx, $null, $null, [ref]$len)
if ($len -le 0) {
    throw "Windows no ve ningun lector. Enchufa el ACR122U y espera a que instale el driver."
}

$buffer = New-Object char[] $len
[void][WinScard]::SCardListReaders($ctx, $null, $buffer, [ref]$len)
$lectores = (-join $buffer).Split([char]0) | Where-Object { $_ }

# Si hay varios lectores nos quedamos con el ACS; el nombre lo pone el driver.
$lector = $lectores | Where-Object { $_ -match "ACR122|ACS" } | Select-Object -First 1
if (-not $lector) { $lector = $lectores[0] }

Write-Host "Lector: $lector"
Write-Host $(if ($SinTeclear) {
    "Modo prueba: muestra los UID sin teclearlos. Ctrl+C para salir."
} else {
    "Puente activo. Deja el navegador enfocado y acerca una tarjeta. Ctrl+C para salir."
})

# ── Bucle de lectura ─────────────────────────────────
# Una tarjeta que se queda apoyada se leeria en cada vuelta del sondeo; sin esto
# la app cobraria varias veces por un solo pasajero. La marca se levanta cuando
# se logra leer y se baja cuando la tarjeta se retira, asi que para volver a
# leerla hay que quitarla y acercarla de nuevo.
$tarjetaPresente = $false
$ausenciasSeguidas = 0

try {
    while ($true) {
        Start-Sleep -Milliseconds $PAUSA_SONDEO_MS

        $card = [IntPtr]::Zero
        $proto = 0
        # Sin tarjeta encima esto falla, que es la forma normal de esperar.
        if ([WinScard]::SCardConnect($ctx, $lector, $SCARD_SHARE_SHARED, $SCARD_PROTOCOL_T0T1, [ref]$card, [ref]$proto) -ne $SCARD_S_SUCCESS) {
            $ausenciasSeguidas++
            if ($ausenciasSeguidas -ge $AUSENCIAS_PARA_REARMAR) { $tarjetaPresente = $false }
            continue
        }
        $ausenciasSeguidas = 0

        try {
            # Es la misma tarjeta de la vuelta anterior, que sigue apoyada.
            if ($tarjetaPresente) { continue }

            # FF CA 00 00 00: "dame el UID". Es el APDU estandar de PC/SC para
            # tarjetas sin contacto, el mismo que usan los lectores HID.
            $io = New-Object WinScard+IO_REQUEST
            $io.Protocol = $proto
            $io.PciLength = 8

            $apdu = [byte[]](0xFF, 0xCA, 0x00, 0x00, 0x00)
            $respuesta = New-Object byte[] 258
            $largo = $respuesta.Length

            if ([WinScard]::SCardTransmit($card, [ref]$io, $apdu, $apdu.Length, [IntPtr]::Zero, $respuesta, [ref]$largo) -ne $SCARD_S_SUCCESS) {
                Write-Warning "Tarjeta detectada pero no respondio al UID"
                continue
            }

            # Los dos ultimos bytes son el codigo de estado: 90 00 es exito.
            if ($largo -lt 2 -or $respuesta[$largo - 2] -ne 0x90) {
                Write-Warning "La tarjeta rechazo la peticion de UID"
                continue
            }

            # La app espera hex plano en mayusculas, igual que lo deja Web NFC.
            $uid = -join ($respuesta[0..($largo - 3)] | ForEach-Object { $_.ToString("X2") })
            if ($uid.Length -lt 4) { continue }

            # Se marca solo despues de una lectura buena: si la tarjeta esta
            # encima pero no logro leerse, se reintenta en la proxima vuelta.
            $tarjetaPresente = $true

            Write-Host "Leido: $uid"

            # SendKeys escribe en la ventana que tenga el foco, que es justo lo
            # que hace un lector HID. El UID es hex, no hay nada que escapar.
            if (-not $SinTeclear) {
                [System.Windows.Forms.SendKeys]::SendWait("$uid{ENTER}")
            }
        }
        finally {
            [void][WinScard]::SCardDisconnect($card, $SCARD_LEAVE_CARD)
        }
    }
}
finally {
    [void][WinScard]::SCardReleaseContext($ctx)
}
