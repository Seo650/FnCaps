# FnCaps

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Українська](README.uk.md) | [Русский](README.ru.md) | [Français](README.fr.md) | Español | [Deutsch](README.de.md)

FnCaps es una app de barra de menús para macOS pensada para quien usa tres o más fuentes de entrada y encuentra lento el cambio entre ellas.

macOS ofrece una sola tecla que recorre todas las fuentes de entrada una tras otra. Con tres o más, hay que pulsar hasta que aparezca el idioma deseado, mirar la barra de menús y volver a pulsar.

FnCaps reparte las fuentes de entrada entre dos teclas: Caps Lock y fn (🌐).

- Cada tecla tiene su propia lista y cambia solo dentro de ella.
- Usted decide qué idioma va en cada tecla. Por ejemplo, el inglés en Caps Lock y los demás idiomas en fn.
- Una lista larga se convierte en dos listas cortas. Con las distribuciones que recomienda FnCaps, el idioma deseado está a una o dos pulsaciones, así que la escritura no se interrumpe.
- Con más idiomas, puede asignar un atajo propio a una fuente de entrada e ir directamente a ella.
- Caps Lock cambia sin retardo. Mantenga la tecla pulsada para activar o desactivar Caps Lock como siempre.

> **Primer inicio:** macOS bloquea FnCaps una vez porque Apple no la ha notarizado. Abra Ajustes del Sistema > Privacidad y seguridad y haga clic en Abrir de todos modos. Los pasos están en [Abrir de todos modos](#open-anyway).

> FnCaps está en desarrollo temprano hasta la versión 1.0.

## Requisitos

- macOS 14 Sonoma o posterior, Apple silicon o Intel
- Permiso de accesibilidad. FnCaps lo necesita para detectar las pulsaciones de fn y Caps Lock.

## Instalación

### Homebrew

```sh
brew install --cask Seo650/tap/fncaps
```

### GitHub Releases

1. Descargue el archivo `FnCaps-x.y.z.zip` más reciente desde [Releases](https://github.com/Seo650/FnCaps/releases/latest).
2. Descomprímalo.
3. Mueva `FnCaps.app` a `/Applications`.

## Primer inicio

<a id="open-anyway"></a>

### Abrir de todos modos

FnCaps está firmada con su propio certificado y Apple no la ha notarizado, así que macOS bloquea el primer inicio. Esto ocurre una sola vez.

1. Abra FnCaps. macOS indica que no puede verificar la app. Haga clic en Listo.
2. Abra Ajustes del Sistema > Privacidad y seguridad.
3. En Seguridad, haga clic en Abrir de todos modos.
4. Introduzca su contraseña o use Touch ID y, después, haga clic en Abrir.

El botón Abrir de todos modos aparece solo después de un inicio bloqueado y permanece alrededor de una hora. Si ya no está, abra FnCaps de nuevo. Si prefiere la línea de comandos, esto elimina el bloqueo:

```sh
xattr -dr com.apple.quarantine /Applications/FnCaps.app
```

### Configuración

Al abrirse, FnCaps le guía por el permiso de accesibilidad y la distribución de las teclas. FnCaps necesita el permiso para detectar las pulsaciones de fn y Caps Lock. Puede cambiar todo más adelante en los ajustes de FnCaps.

## Actualizaciones

FnCaps busca una versión nueva una vez al día. Para instalarla, abra los ajustes de FnCaps, vaya a Acerca de FnCaps y haga clic en Actualizar. No se instala nada hasta que haga clic en Actualizar. Los usuarios de Homebrew actualizan de la misma forma.

Las actualizaciones conservan el permiso de accesibilidad, porque cada versión está firmada con el mismo certificado.

## Qué envía FnCaps

FnCaps no registra lo que escribe. Se conecta a Internet en dos casos.

- Comprobación de actualizaciones: una vez al día, FnCaps pide a la API de GitHub la última versión. La solicitud incluye la versión de la app y nada más sobre usted.
- Reportar error: no se envía nada hasta que haga clic en Enviar. Un informe contiene su mensaje, su correo si lo indica, las versiones de la app y de macOS, el modelo de Mac, el tipo de teclado, sus ajustes de FnCaps, sus fuentes de entrada, el registro de actividad reciente y un número de instalación aleatorio que solo se usa para el límite diario. No contiene lo que escribe, números de serie ni otros identificadores del dispositivo. Puede leer todo antes de enviarlo. Los informes se guardan en un repositorio privado que solo el desarrollador puede leer.
- Límites de informes: cinco informes al día por instalación y cinco por minuto desde una misma dirección de red.

## Limitaciones conocidas

- Campos de contraseña: macOS mantiene los campos de contraseña en inglés, así que FnCaps no cambia de idioma ahí, y mantener pulsada Caps Lock no activa Bloqueo Mayúsculas.
- Control+Space: no cambia de fuente de entrada mientras FnCaps está activada. Vuelve a funcionar al desactivar o cerrar FnCaps.
- Luz de Caps Lock: al activar Bloqueo Mayúsculas manteniendo pulsada la tecla, la luz de la tecla permanece apagada. Las mayúsculas se escriben con normalidad.
- Indicador de idioma: al pulsar las teclas rápido, el pequeño indicador que macOS muestra junto al cursor puede mostrar un idioma distinto del que se está usando. La barra de menús muestra el correcto.
- Carácter en composición: si un carácter coreano, japonés o chino todavía se está componiendo al pulsar fn, ese carácter puede perderse.
- Distribución inglesa: FnCaps trata ABC y U.S. como inglés. ABC – AZERTY y ABC – QWERTZ cuentan como francés y alemán.
- Karabiner-Elements y gksdud: estas apps cambian las mismas teclas. Una regla de Karabiner que use `caps_lock` toma la tecla antes de que FnCaps la vea. FnCaps muestra un aviso mientras una de ellas está en ejecución.
- Sin probar, se espera que funcione: desconectar y volver a conectar un teclado externo, macOS 14 a 26 y Macs distintos de un MacBook Air con Apple silicon.

## Recuperación

Si Caps Lock deja de funcionar:

- En FnCaps, elija Restaurar teclas en el icono de la barra de menús, o haga clic en Restaurar ahora en Ajustes > General. Esto devuelve Caps Lock y el atajo de fuente de entrada a como estaban antes de FnCaps.
- Si FnCaps no está en ejecución, por ejemplo tras un cierre inesperado, Caps Lock puede quedar reasignada y no hacer nada. Elimine la reasignación en Terminal y abra FnCaps de nuevo:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

- Si clonó este repositorio, el script elimina la reasignación y también restaura el atajo de fuente de entrada:

  ```sh
  scripts/caps-recover.sh --restore
  ```

Si Control+Space sigue sin cambiar de fuente de entrada después de cerrar FnCaps, revise Ajustes del Sistema > Teclado > Atajos de teclado > Fuentes de entrada > «Seleccionar la fuente de entrada anterior». Restaurar teclas lo devuelve a como estaba antes de FnCaps.

## Desinstalación

Cierre FnCaps primero. Al cerrarla, Caps Lock y el atajo de fuente de entrada vuelven a como estaban. Después, ejecute:

```sh
brew uninstall --cask fncaps
```

O mueva `FnCaps.app` de `/Applications` a la Papelera. Para quitar también los ajustes, use `brew uninstall --zap --cask fncaps`.

## Compilar desde el código fuente

```sh
swift build
scripts/build-app.sh
```

`scripts/build-app.sh` crea `build/FnCaps.app`. Firma con el certificado «FnCaps Dev Local» cuando existe y con una firma ad hoc en caso contrario. Con una firma ad hoc, macOS vuelve a pedir el permiso de accesibilidad después de cada compilación. `scripts/make-local-identity.sh` crea el certificado local.

## Contribuir

Las incidencias y las solicitudes de cambio son bienvenidas. La app y este README están traducidos a diez idiomas. La mayoría de las traducciones no las revisaron hablantes nativos, así que las correcciones de traducción son especialmente bienvenidas.

## Licencia

MIT. Consulte [LICENSE](LICENSE).
