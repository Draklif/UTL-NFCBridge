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

    Uso:  .\puente.ps1               teclea el UID en la ventana activa
          .\puente.ps1 -SinTeclear   solo lo muestra en consola (para probar)
          .\puente.ps1 -SinEnter     teclea el UID pero no cierra con Enter
          .\puente.ps1 -Minusculas   teclea el UID en minusculas

    O, para no acordarse de nada de esto, doble clic en Puente.bat: trae un menu
    con los mismos modos y opciones.
#>

param(
    # Solo muestra los UID en pantalla, sin teclear nada. Para probar el lector.
    [switch]$SinTeclear,

    # Algunas apps procesan el campo solas y un Enter de mas les envia el
    # formulario antes de tiempo.
    [switch]$SinEnter,

    # Por si la app compara el UID como texto y lo guarda en minusculas.
    [switch]$Minusculas
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

    // Windows avisa cuando cambia el estado del lector, en vez de que nosotros
    // preguntemos cada tanto. Es la diferencia entre reaccionar al instante y
    // reaccionar cuando toque el siguiente sondeo.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct READERSTATE {
        public string Reader;
        public IntPtr UserData;
        public uint CurrentState;
        public uint EventState;
        public uint AtrLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 36)]
        public byte[] Atr;
    }

    [DllImport("winscard.dll", CharSet = CharSet.Unicode)]
    public static extern int SCardGetStatusChange(IntPtr ctx, uint timeout, [In, Out] READERSTATE[] states, int count);
}
"@

$SCARD_SCOPE_USER      = 0
$SCARD_SHARE_SHARED    = 2
$SCARD_PROTOCOL_T0T1   = 3
$SCARD_LEAVE_CARD      = 0
$SCARD_S_SUCCESS       = 0
$SCARD_STATE_UNAWARE   = 0
$SCARD_STATE_PRESENT   = 0x20
$SCARD_E_TIMEOUT       = 0x8010000A

# El bloque de espera no se puede interrumpir con Ctrl+C mientras corre, asi que
# se corta cada tanto y se vuelve a entrar. Medio segundo no se siente.
$ESPERA_MAX_MS = 500

# La tarjeta puede tardar un instante en quedar lista despues de que el lector
# avisa que ya esta encima: hasta medio segundo insistiendo, que en la practica
# se resuelve en el primer o segundo intento.
$REINTENTOS_LECTURA = 16
$PAUSA_REINTENTO_MS = 30

# Escribir en la ventana activa.
#
# Aqui NO se usa System.Windows.Forms.SendKeys: por dentro se apoya en journal
# hooks, un mecanismo viejo que Windows puede reinyectar entero si el enganche se
# interrumpe. El sintoma es el UID repetido y entrelazado consigo mismo
# (CA8C0943 llegando como CCCAAA88CC00...), y no hay forma de ajustarlo.
#
# SendInput es la API con la que el propio Windows entrega las pulsaciones de un
# teclado real: una sola llamada, todo el UID de una vez, sin reinyeccion. Y en
# modo unicode manda el caracter tal cual, asi que no depende de la distribucion
# del teclado (en un teclado AZERTY la A y la Q estan cambiadas de sitio, y con
# codigos de tecla saldria el UID mal escrito).
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Teclado {
    const uint INPUT_KEYBOARD    = 1;
    const uint KEYEVENTF_KEYUP   = 0x0002;
    const uint KEYEVENTF_UNICODE = 0x0004;
    const ushort VK_RETURN       = 0x0D;

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT {
        public ushort Vk;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }

    // INPUT es una union en C: la variante de raton es mas grande que la de
    // teclado, y el relleno iguala el tamano que espera Windows.
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT {
        public uint Type;
        public KEYBDINPUT Tecla;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public byte[] Relleno;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint count, INPUT[] inputs, int size);

    static INPUT Pulsacion(ushort vk, char caracter, bool soltar) {
        INPUT i = new INPUT();
        i.Type = INPUT_KEYBOARD;
        i.Relleno = new byte[8];
        i.Tecla.Vk = vk;
        i.Tecla.Scan = (ushort)caracter;
        i.Tecla.Flags = (vk == 0 ? KEYEVENTF_UNICODE : 0) | (soltar ? KEYEVENTF_KEYUP : 0);
        return i;
    }

    // Devuelve cuantas pulsaciones acepto Windows; menos de las enviadas
    // significa que algo las bloqueo.
    public static uint Escribir(string texto, bool conEnter) {
        int n = texto.Length * 2 + (conEnter ? 2 : 0);
        INPUT[] eventos = new INPUT[n];

        int k = 0;
        foreach (char c in texto) {
            eventos[k++] = Pulsacion(0, c, false);
            eventos[k++] = Pulsacion(0, c, true);
        }
        if (conEnter) {
            eventos[k++] = Pulsacion(VK_RETURN, '\0', false);
            eventos[k++] = Pulsacion(VK_RETURN, '\0', true);
        }

        return SendInput((uint)n, eventos, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@

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

# Un intento de lectura. Devuelve el UID en hex, o $null si todavia no se puede.
function Intentar-Leer {
    param([IntPtr]$Contexto, [string]$Lector)

    $card = [IntPtr]::Zero
    $proto = 0

    if ([WinScard]::SCardConnect($Contexto, $Lector, $SCARD_SHARE_SHARED, $SCARD_PROTOCOL_T0T1, [ref]$card, [ref]$proto) -ne $SCARD_S_SUCCESS) {
        return $null
    }

    try {
        # FF CA 00 00 00: "dame el UID". Es el APDU estandar de PC/SC para
        # tarjetas sin contacto, el mismo que usan los lectores HID.
        $io = New-Object WinScard+IO_REQUEST
        $io.Protocol = $proto
        $io.PciLength = 8

        $apdu = [byte[]](0xFF, 0xCA, 0x00, 0x00, 0x00)
        $respuesta = New-Object byte[] 258
        $largo = $respuesta.Length

        if ([WinScard]::SCardTransmit($card, [ref]$io, $apdu, $apdu.Length, [IntPtr]::Zero, $respuesta, [ref]$largo) -ne $SCARD_S_SUCCESS) {
            return $null
        }

        # Preguntamos apenas la tarjeta entra al campo, asi que a veces alcanza a
        # contestar "todo bien" sin el UID todavia. Un UID son 4, 7 o 10 bytes,
        # mas los dos del codigo de estado: menos de 6 en total es una respuesta
        # incompleta, no una tarjeta rara.
        if ($largo -lt 6) { return $null }

        # Los dos ultimos bytes son el codigo de estado: 90 00 es exito.
        if ($respuesta[$largo - 2] -ne 0x90 -or $respuesta[$largo - 1] -ne 0x00) {
            return $null
        }

        # La app espera hex plano en mayusculas, igual que lo deja Web NFC.
        return -join ($respuesta[0..($largo - 3)] | ForEach-Object { $_.ToString("X2") })
    }
    finally {
        [void][WinScard]::SCardDisconnect($card, $SCARD_LEAVE_CARD)
    }
}

# Lee el UID de la tarjeta que este encima del lector, o $null si no se pudo.
# Insiste un poco: entre que Windows avisa que hay tarjeta y que la tarjeta
# realmente puede contestar pasan unos milisegundos.
function Leer-Uid {
    param([IntPtr]$Contexto, [string]$Lector)

    for ($i = 0; $i -lt $REINTENTOS_LECTURA; $i++) {
        $uid = Intentar-Leer -Contexto $Contexto -Lector $Lector
        if ($uid) { return $uid }
        Start-Sleep -Milliseconds $PAUSA_REINTENTO_MS
    }

    Write-Warning "Tarjeta detectada pero no entrego un UID valido. Retirala y vuelve a acercarla."
    return $null
}

# ── Bucle de lectura ─────────────────────────────────
# Una lectura por tarjeta apoyada: se lee al detectar que entra, y no se vuelve
# a leer hasta que se retire y se acerque de nuevo. Sin esto la app cobraria dos
# veces por un solo pasajero.

# READERSTATE es un struct, y PowerShell entrega una copia al indexar el array:
# escribirle campos ahi dentro no llega al original. Hay que armarlo aparte y
# meterlo entero, y lo mismo al actualizarlo mas abajo.
$st = New-Object WinScard+READERSTATE
$st.Reader = $lector
$st.CurrentState = $SCARD_STATE_UNAWARE
$st.Atr = New-Object byte[] 36

$estado = [WinScard+READERSTATE[]]@($st)

$tarjetaPresente = $false

try {
    while ($true) {
        # Aqui el proceso queda dormido hasta que algo cambia en el lector: no
        # gasta CPU y reacciona en cuanto la tarjeta toca la antena.
        $r = [WinScard]::SCardGetStatusChange($ctx, $ESPERA_MAX_MS, $estado, 1)

        if ($r -eq $SCARD_E_TIMEOUT) { continue }
        if ($r -ne $SCARD_S_SUCCESS) {
            throw "Se perdio el lector. Revisa que el ACR122U siga conectado."
        }

        # Lo que Windows reporta ahora es el punto de partida de la proxima espera.
        $st = $estado[0]
        $st.CurrentState = $st.EventState
        $estado[0] = $st

        $hayTarjeta = ($st.EventState -band $SCARD_STATE_PRESENT) -ne 0

        if (-not $hayTarjeta) {
            $tarjetaPresente = $false
            continue
        }

        # Sigue siendo la misma tarjeta apoyada desde antes: ya se leyo.
        if ($tarjetaPresente) { continue }
        $tarjetaPresente = $true

        $uid = Leer-Uid -Contexto $ctx -Lector $lector
        if (-not $uid) { continue }

        if ($Minusculas) { $uid = $uid.ToLower() }

        Write-Host "Leido: $uid"

        # Las pulsaciones van a la ventana que tenga el foco, que es justo lo que
        # hace un lector HID.
        if (-not $SinTeclear) {
            $esperadas = $uid.Length * 2 + $(if ($SinEnter) { 0 } else { 2 })
            $aceptadas = [Teclado]::Escribir($uid, (-not $SinEnter))

            # Windows no deja que un programa normal teclee dentro de uno que
            # corre como administrador. Si la app va elevada, el puente tiene que
            # ir elevado tambien.
            if ($aceptadas -lt $esperadas) {
                Write-Warning "Windows bloqueo las pulsaciones. Si la app corre como administrador, abre el puente como administrador tambien."
            }
        }
    }
}
finally {
    [void][WinScard]::SCardReleaseContext($ctx)
}
