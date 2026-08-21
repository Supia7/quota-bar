# QuotaBar

**Un monitor nativo de la barra de menús de macOS para el uso de suscripciones OAuth de Claude y Codex.**

Compara varias cuentas por cuenta o por tipo de límite, y controla los alias y la visibilidad del correo electrónico.

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

> **Estado:** Primera versión pública. Los endpoints de uso de Claude y Codex no son APIs públicas y estables de billing; son endpoints internos usados por sus coding clients. Si cambian, QuotaBar muestra un error explícito en lugar de inventar datos.

## Capturas

> Estas capturas usan **datos de ejemplo** sin credenciales conectadas. No contienen tokens ni información real de cuentas.

<table>
  <tr>
    <td width="50%"><img src="docs/images/quotabar-accounts.png" alt="Vista de cuentas de Claude y Codex"></td>
    <td width="50%"><img src="docs/images/quotabar-limit-types.png" alt="Vista agrupada por límites de cinco horas, Weekly y Fable"></td>
  </tr>
  <tr>
    <td align="center"><sub>Vista por cuentas</sub></td>
    <td align="center"><sub>Vista por tipo de límite</sub></td>
  </tr>
</table>

## ¿Qué muestra?

### Claude

- Ventana rolling de cinco horas
- Límite Weekly para todos los modelos
- Límite Weekly específico de Fable/model-scoped
- Si el provider no devuelve datos de Fable, muestra `Unavailable` en vez de inventar un 0%

### Codex

- Límite Weekly de la suscripción OAuth
- Porcentaje restante y hora de reset

### Gestión de cuentas

- Sin límite fijo de cuentas
- UUID estable por cuenta; dos cuentas con el mismo correo siguen siendo independientes
- Alias local editable
- Mostrar u ocultar el correo por cuenta
- Vistas `Accounts` y `Limit types`
- La vista elegida se guarda localmente

## Instalación

### Para usuarios — DMG recomendado

1. Descarga `QuotaBar-macos-arm64.dmg` desde [Releases](https://github.com/Supia7/quota-bar/releases/latest).
2. Abre el DMG y arrastra `QuotaBar.app` a `Applications`.
3. En el primer inicio, si macOS muestra una advertencia, haz clic derecho sobre la app y elige **Abrir**.

Los artefactos actuales están firmados ad-hoc. Hasta añadir una firma Developer ID y notarización de Apple, Gatekeeper puede pedirte confirmar el desarrollador.

### Terminal — instalar la última release

Después de clonar el repositorio, ejecuta este comando. Descarga la release correspondiente a la arquitectura del Mac, verifica el checksum y la instala en `~/Applications`.

```bash
./Scripts/install-release.sh
```

### Desarrolladores — compilar e instalar desde el código

```bash
./Scripts/install.sh
```

Compila el binario release, crea el bundle `.app`, aplica una firma ad-hoc, lo copia a `~/Applications/QuotaBar.app` y lo abre.


### Requisitos

- macOS 26+
- Swift 6.2+
- JSON de credenciales OAuth gestionado por Claude Code o Codex

### Compilar y ejecutar

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBar
```

`QuotaBarPreview` muestra la misma UI Monitor en una ventana normal para desarrollo y revisión visual.

### Conectar una cuenta

Abre Settings, elige `Add OAuth account` y selecciona el archivo JSON de credenciales del provider.

| Provider | Archivo de credenciales predeterminado |
| --- | --- |
| Claude | `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json` |

QuotaBar solo guarda la ruta y las preferencias de visualización. No copia access tokens ni refresh tokens a sus propios archivos JSON y no ofrece un campo para pegar tokens.

## Límite de seguridad

- Solo OAuth; los datos de billing de una API key no se tratan como quota de suscripción
- Las credenciales se leen de los archivos gestionados por el provider al actualizar
- Los tokens nunca se guardan en la persistencia de QuotaBar
- Claude y Codex usan políticas de host/path HTTPS fijas
- Los redirects HTTP se rechazan
- No hay scraping de cookies de Claude Web
- No se ejecutan CLI externos
- No hay telemetry ni analytics
- Si falla una actualización, se mantiene la última pantalla válida
- Si el token caduca, se muestra un estado de reautenticación sin ejecutar un CLI en silencio

> Los endpoints de uso OAuth de Claude y de suscripción de Codex no son APIs públicas estables. Si cambia el schema o el rate limit, QuotaBar muestra un error explícito y no una estimación.

## Datos locales

| Ubicación | Contenido |
| --- | --- |
| `~/Library/Application Support/QuotaBar/accounts.json` | provider, alias, email, visibilidad del email y ruta de credenciales |
| `~/Library/Application Support/QuotaBar/display-preferences.json` | alias y visibilidad del email por cuenta |

Los access/refresh tokens de OAuth no se escriben en estos archivos.

## Guía para desarrolladores

```text
Sources/QuotaBarCore/       modelos, decoders, credential boundary y provider client
Sources/QuotaBarUI/         UI de menú, dos vistas, polling y editor de cuentas
Sources/QuotaBar/            entrada de la aplicación de menú
Sources/QuotaBarPreview/     entrada del Preview en ventana
Sources/QuotaBarChecks/      self-check sin framework
```

Verificación:

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
git diff --check
```

El entorno actual de Command Line Tools no expone los módulos XCTest/Testing, por lo que el repositorio usa un ejecutable self-check sin framework.

## Roadmap

- Fallback de credenciales en Keychain gestionadas por el provider
- Obtener el email automáticamente mediante profile endpoints de Claude/Codex
- Tarjetas de estado stale / re-auth por cuenta
- Revisar la rotación de tokens OAuth y los flujos OAuth oficiales
- Test target completo de Xcode y pipeline de releases firmado/notarizado

## Licencia

QuotaBar se distribuye bajo la [MIT License](LICENSE). Se permiten el uso comercial, las modificaciones, la redistribución y los forks; conserva el aviso de copyright y la licencia.

## Repository

- GitHub: <https://github.com/Supia7/quota-bar>
- Plan: [`docs/2026-08-21-multi-account-oauth-plan.md`](docs/2026-08-21-multi-account-oauth-plan.md)
- Requirements: [`docs/2026-08-21-multi-account-oauth-requirements.md`](docs/2026-08-21-multi-account-oauth-requirements.md)
