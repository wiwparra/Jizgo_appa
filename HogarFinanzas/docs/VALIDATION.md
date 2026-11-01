# Validación y límites

Entorno observado: Debian 13 x86_64, Swift 6.2.1 (distribución oficial Ubuntu 24.04 compatible con las bibliotecas instaladas). Se verificó la firma GPG con la clave oficial Swift 6.x, huella `52BB 7E3D E28A 71BE 22EC 05FF EF80 A866 B47A 981F`, obtenida del repositorio oficial de Swift. Se mantuvieron TLS y comprobaciones de firma; no se deshabilitó verificación.

## Ejecutado

- Compilación de `HogarCore` con Swift Package Manager: aprobada.
- `./Scripts/test.sh`: **58 pruebas XCTest, 0 fallos** (las 39 anteriores, 14 de avisos bancarios y 5 de etiquetas). La salida completa de esta ejecución está en `docs/test-output.txt`.
- Seis pruebas originales puras del prototipo: **6 aprobadas**, cuerpos sin cambios, con `Finance.swift` original dentro de un paquete temporal. No se compilaron sus clases SwiftUI. Son evidencia del prototipo, no 6 pruebas adicionales del nuevo paquete.
- Análisis sintáctico de las nueve fuentes SwiftUI con `swiftc -frontend -parse`: aprobado. Esto no resuelve tipos/importaciones Apple ni prueba la interfaz.
- Parseo OpenStep del archivo `project.pbxproj` con Foundation, verificación de los nueve archivos fuente referenciados y XML del esquema/entitlements: aprobado. No equivale a abrir el proyecto en Xcode.
- Script de instalación del entorno: ejecutado con firma y dependencias almacenadas; comprobada la repetibilidad sin modificar código ni lockfiles.

El pie de Swift Testing informa «0 tests» porque el proyecto usa XCTest. Los 58 casos ejecutados aparecen en la suite XCTest y en la salida conservada; no se cuenta el runner vacío de Swift Testing como validación.

Casos cubiertos: precisión/validación, saldo inicial, transferencias neutras, saldo por cuenta, edición y tombstones, periodos Madrid con cambio de año/DST y febrero bisiesto, filtros, reservas/límites/liberación/sobregasto/vencimientos, historial presupuestario, permisos de mutación por autor y administrador, salida/revocación lógica local, conflictos/reintentos del reductor, servicio no configurado, persistencia/permisos de archivo, copias/confirmación/archivos corruptos, referencias inválidas, importación del esquema antiguo y autoría desconocida.

## No ejecutado

- Compilación macOS/iOS Simulator, firma, instalación y ejecución de la aplicación: bloqueadas por ausencia de macOS/Xcode/SDK. El script Apple detecta este caso y termina con error explícito; no informa éxito.
- Las tres StoreTests originales que importan SwiftUI.
- Formularios, selectores de archivos, restauración desde la interfaz, modo oscuro, Dynamic Type, VoiceOver, navegación Mac, teclado y uso de varias ventanas: pendientes de ejecución Apple. Se incluyeron las fuentes y controles, sin afirmar validación visual.
- Invitaciones, acceso entre cuentas independientes, edición sin conexión con reconciliación remota, notificaciones y revocación remota: no implementados ni probados. El reductor puro no cubre estos casos integrales.
- Restauración del snapshot en una nueva tarea cloud y publicación del entorno: pendientes de la interfaz de la plataforma.

## Prueba manual Apple

1. Crear hogar real sin datos de demostración; añadir Banco con 1.000 € y Efectivo con 0 €.
2. Registrar ingreso de 2.000 € y gasto de 500 €: saldo total 2.500 €, ingreso 2.000 €, gasto 500 €.
3. Crear meta de 1.000 €, reservar 600 €: saldo sin reservar 1.900 €, gasto permanece 500 €.
4. Transferir 300 € de Banco a Efectivo: total 2.500 €, ingresos/gastos sin cambios; cuentas 2.200 € y 300 €.
5. Editar y eliminar un movimiento (cancelar y confirmar); comprobar recálculo y persistencia al reabrir.
6. Cambiar de mes, establecer límites distintos, volver al mes anterior y comprobar historial.
7. Reservar más de lo posible, liberar más de lo reservado y reducir objetivo por debajo de su reserva: errores claros, estado intacto. Gastar después de reservar y comprobar aviso de falta de cobertura.
8. Exportar, cambiar datos, seleccionar copia, cancelar restauración y comprobar que nada cambia; repetir confirmando. Probar JSON corrupto y versión no soportada. No usar archivos financieros reales para estas pruebas.
9. Importar una copia 0.1 y verificar las advertencias, la cuenta conjunta, los nombres atribuidos y los autores desconocidos.
10. Activar demostración, modificarla y volver al modo real: comprobar separación. Repetir con VoiceOver, texto grande, contraste oscuro y teclado.

## Incremento de avisos y etiquetas

Se ejecutaron 19 pruebas nuevas: importes españoles, agrupación, decimal con punto, moneda explícita, dirección ambigua, transferencias, varias cantidades, saldos, moneda extranjera, códigos de seguridad, pagos rechazados/pendientes, límites de entrada, confirmación sin mutación previa, reintento idempotente, posible duplicado con confirmación separada, tombstone y permisos; etiquetas, búsqueda, copia antigua sin campo tags y conservación de saldos. No se guarda el texto del aviso en la copia financiera.

El OCR de Vision, la selección de fotos, la presentación de la hoja y la compilación nativa siguen pendientes de Apple. Se validaron la sintaxis de las nueve fuentes y las referencias del proyecto, no su ejecución. No se añadieron capacidades de iCloud ni App Groups al proyecto local. La colaboración continúa deshabilitada; se consultó ahora la documentación oficial de Core Data/CloudKit con éxito (ICLOUD.md).
