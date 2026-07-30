# UTL-NFCBridge

Convierte un lector NFC **ACR122U** en un teclado: lee el UID de la tarjeta y lo
escribe como pulsaciones en la ventana activa, terminando con Enter.

Un solo archivo de PowerShell, sin nada que instalar.

## Para qué sirve

Los navegadores de escritorio no exponen lectores NFC a JavaScript — Web NFC solo
existe en Chrome para Android. Por eso muchas apps web aceptan la entrada por
teclado, pensando en los lectores HID que teclean el UID y cierran con Enter.

El ACR122U no sirve para eso porque no es un teclado, sino un lector PC/SC. Este
puente traduce entre los dos mundos, y para la app receptora resulta
indistinguible de un lector HID. No hay que cambiar nada de su lado.

Sirve para cualquier cosa que sepa recibir un UID tecleado: una app web, un campo
de formulario, una hoja de cálculo o el Bloc de notas.

## Uso

Doble clic en **`Puente.bat`**. Eso es todo: no hay que abrir la consola ni pelear
con la política de ejecución, porque el `.bat` la esquiva solo para ese proceso
(no cambia ninguna configuración del PC).

**`Puente (prueba).bat`** hace lo mismo pero sin teclear: solo muestra los UID en
pantalla. Empieza siempre por ahí — si el UID no aparece, el problema está en el
lector y no en la app que lo recibe.

Desde PowerShell, si lo prefieres:

```powershell
.\puente.ps1 -SinTeclear     # muestra los UID en consola, no teclea nada
.\puente.ps1                 # el modo real
```

Con el puente corriendo, deja **enfocada** la ventana donde quieres que aparezca
el UID y acerca la tarjeta.

El UID sale en hex plano y mayúsculas (`04A1B2C3`), el mismo formato que entrega
Web NFC en Android una vez se le quitan los dos puntos.

## Una lectura por tarjeta

El puente lee **una sola vez** cada vez que se acerca una tarjeta. Si se queda
apoyada sobre el lector no vuelve a leerla: hay que retirarla y acercarla otra
vez. Así una misma tarjeta no puede cobrar dos veces por descuido.

No es un antirrebote por tiempo, sino el estado real del lector: se lee en el
momento en que la tarjeta entra al campo, y no se vuelve a leer hasta que sale.

## Velocidad

No hay sondeo. El proceso queda dormido dentro de `SCardGetStatusChange`, la
función con la que Windows avisa cuando algo cambia en el lector, y despierta en
el instante en que la tarjeta toca la antena. El retardo es el del lector, no el
del script — y mientras espera no consume CPU.

## Un .exe, si lo quieres

`Puente.bat` ya se abre con doble clic, así que el `.exe` no hace falta. Si de
todos modos prefieres repartir un archivo suelto, sin el `.ps1` al lado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File construir-exe.ps1
```

Instala [ps2exe](https://github.com/MScholtes/PS2EXE) para tu usuario (sin
administrador) y deja `Puente.exe` en la carpeta. Dos advertencias: adentro sigue
siendo el mismo script —no compila nada, no es más rápido— y **los antivirus
desconfían de los ejecutables de ps2exe**, porque el malware usa la misma técnica
para esconder scripts. Si Defender lo borra, reparte el `.bat`.

Por eso `Puente.exe` no está versionado: para los estudiantes, clonar el repo y
hacer doble clic en `Puente.bat` es el camino que no falla.

## Requisitos

Ninguno que haya que instalar. `winscard.dll` —la API de tarjetas inteligentes—
viene en todo Windows, el ACR122U lo toma el driver CCID nativo y el servicio
*Smart Card* (`SCardSvr`) arranca solo. No hace falta Node, ni Python, ni
compilador, ni permisos de administrador: está pensado para poder correrlo en un
PC prestado o institucional.

No instales el driver de ACS ni pases el lector por Zadig. Eso es para libnfc y
deja el lector invisible para PC/SC, que es justo lo que este puente usa.

## Solo Windows, y por qué

Las alternativas se probaron y se descartaron:

- **WSL no funciona.** Se le puede pasar el lector con `usbipd-win` y WSL llega a
  verlo (`lsusb` lo muestra, el driver CCID carga), pero el handshake inicial no
  sobrevive el viaje por USB/IP: `pcscd` falla con `Invalid frame detected` y
  `LIBUSB_ERROR_TIMEOUT`. El ACR122U depende de un timing que el passthrough por
  red no reproduce. No hay configuración que lo arregle.
- **Node exige compilador.** `@pokusew/pcsclite`, el binding PC/SC de npm, no
  publica binarios precompilados: siempre corre `node-gyp rebuild` y pide Visual
  Studio Build Tools. Varios GB y permisos de administrador.

PowerShell habla con `winscard.dll` directamente y evita las dos cosas. En Linux
nativo el equivalente sería `pcscd` con cualquier binding, y ahí sí funciona: el
problema es exclusivamente el passthrough USB de WSL.

## Límites

- El ACR122U solo lee **NFC-A**. Una tarjeta NFC-B no la detecta.
- El UID se teclea en la ventana activa, así que esa ventana debe tener el foco.
- Una tarjeta apoyada se lee una vez; para releerla hay que retirarla y volver a
  acercarla.
- Si se desconecta el lector con el puente corriendo, el script se detiene con un
  aviso en vez de quedarse esperando en falso.
- Si hay varios lectores conectados, elige el que tenga `ACR122` o `ACS` en el
  nombre; si no encuentra ninguno, toma el primero de la lista.
