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

Doble clic en **`Puente.bat`**: sale un menú para elegir el modo (`1`) y arrancar
(`I`). El `.bat` solo lanza el script —no interviene en la lectura— y esquiva la
política de ejecución solo para ese proceso, sin cambiar nada del PC. Si hay un
`Puente.exe` al lado, usa ese.

Desde PowerShell es lo mismo:

```powershell
.\puente.ps1 -SinTeclear     # muestra los UID en consola, no teclea nada
.\puente.ps1                 # el modo real
```

Si PowerShell bloquea el script por política de ejecución:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File puente.ps1
```

Con el puente corriendo, deja **enfocada** la ventana donde quieres que aparezca
el UID y acerca la tarjeta.

Empieza siempre por `-SinTeclear`. Si ahí no aparece el UID, el problema está en
el lector y no en la app que lo recibe.

El UID sale en hex plano y mayúsculas (`04A1B2C3`), el mismo formato que entrega
Web NFC en Android una vez se le quitan los dos puntos.

## El .exe

`Puente.exe` se publica en [Releases](../../releases), no en el repo: es un
binario que no aporta nada al historial y que algunos antivirus miran mal cuando
llega al clonar. Adentro es el mismo script; sirve para repartir un archivo
suelto a quien no vaya a clonar.

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
- Una tarjeta que se queda apoyada se lee **una sola vez**. Para volver a leerla
  hay que retirarla y acercarla de nuevo.
- Con la tarjeta quieta encima, el ACR122U falla de vez en cuando una vuelta del
  sondeo (`SCARD_W_REMOVED_CARD`) y a la siguiente vuelve a responder. Por eso
  hacen falta 3 vueltas seguidas sin tarjeta —750 ms— para admitir una lectura
  nueva (`AUSENCIAS_PARA_REARMAR`): sin ese margen, el parpadeo del lector se
  confunde con haber retirado la tarjeta y se producen lecturas repetidas.
- Sondea cada 250 ms (`PAUSA_SONDEO_MS`), así que hay un retardo de hasta esa
  cantidad entre apoyar la tarjeta y la lectura.
- Si hay varios lectores conectados, elige el que tenga `ACR122` o `ACS` en el
  nombre; si no encuentra ninguno, toma el primero de la lista.
