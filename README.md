# Hogar Finanzas

Proyecto nativo SwiftUI para iPhone (iOS 17+) y Mac (macOS 14+), con núcleo Swift compartido sin dependencias externas. Interfaz española y EUR.

**Entrega parcial verificable: núcleo local probado; interfaz Apple y colaboración familiar sin validar. No es una aplicación terminada.**

Abre [HogarFinanzas.xcodeproj](HogarFinanzas/HogarFinanzas.xcodeproj) en Xcode 16 o posterior. Selecciona el esquema HogarFinanzas, My Mac o un simulador de iPhone y ejecuta. Para dispositivo físico selecciona tu equipo y un bundle identifier propio en Signing & Capabilities. No se incluyen certificados, claves ni conexión bancaria.

Para probar el núcleo:

```sh
cd HogarFinanzas
./Scripts/test.sh
```

En Linux el entorno preparado tiene Swift 6.2.1 en `/workspace/toolchains`. En un Mac el script usa el Swift de Xcode. Para compilar ambos destinos Apple y repetir las pruebas del núcleo:

```sh
cd HogarFinanzas
./Scripts/validate-apple.sh
```

Ese último script **no se ha ejecutado aquí**: Linux no dispone de Xcode, SDK de Apple ni simulador. Consulta [validación](HogarFinanzas/docs/VALIDATION.md).

Implementado:

- Cuentas manuales con saldo inicial; ingresos, gastos y transferencias; edición y eliminación confirmada; búsqueda por concepto/notas y filtros por mes, categoría, cuenta y miembro atribuido.
- Resumen con saldo por cuenta y total, ingresos/gastos/resultado mensual, reservas y saldo sin reservar; evolución de seis meses y distribución del gasto. Se explican las cifras y la falta de cobertura de reservas.
- Presupuestos por categoría y mes con historial independiente, consumo, restante y exceso.
- Metas con creación, edición, eliminación confirmada, vencimiento, aportación mensual, reserva y liberación. Las reservas no generan gastos ni transferencias y no pueden superar el saldo sin reservar.
- Persistencia local atómica, validación de referencias/importes/versiones, bloqueo ante archivos ilegibles, exportación JSON y restauración validada y confirmada.
- Importación de copias JSON del prototipo 0.1, con advertencias sobre cuenta conjunta, autoría desconocida e historial de presupuestos inexistente.
- Navegación con pestañas en iPhone y barra lateral en Mac; formatos españoles, modo oscuro del sistema, fuentes dinámicas, etiquetas accesibles y acceso rápido a nuevo gasto (⌘N en Resumen).
- Demostración explícita y separada del archivo real. Ningún dato de ejemplo se inserta al crear un hogar real.

La lógica de permisos y el reductor de conflictos/reintentos están probados de forma local. **No hay autenticación familiar, invitaciones, transporte de sincronización ni revocación remota implementados.** Se informa «Solo en este dispositivo»; el código no simula sincronización. [Evaluación de iCloud y requisitos pendientes](HogarFinanzas/docs/ICLOUD.md).

El [informe del prototipo](HogarFinanzas/docs/PROTOTYPE_AUDIT.md) explica lo reutilizado y las diferencias. No se modifica el ZIP original. Los datos del prototipo no se detectan ni reemplazan automáticamente: exporta allí su copia y selecciónala en Hogar y copias de esta versión. Antes de reemplazar, exporta también el hogar actual.

Los JSON exportados están en claro. El archivo de iOS usa protección completa; en Mac se emplean sandbox y permisos de archivo. No hay cifrado propio, analítica ni registros de datos financieros. No se ha publicado la app ni contratado ningún servicio.
