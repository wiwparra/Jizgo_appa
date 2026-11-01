# Validación y límites actuales

Entorno: Debian 13 x86_64, Swift 6.2.1 oficial (distribución Ubuntu 24.04 compatible con estas bibliotecas), PostgreSQL 17 efímero en Docker. Se mantuvieron TLS, firma GPG de Swift y verificación de capas/digest de la imagen oficial PostgreSQL; no se deshabilitaron comprobaciones.

## Ejecutado

- **78 pruebas XCTest Swift: 0 fallos.** Salida de la ejecución actual en `test-output.txt`. Incluyen las 58 anteriores más 20 de cola, repositorio familiar, recuperación y cliente HTTP.
- **23 pruebas de PostgreSQL real: 0 fallos.** Salida en `../../Supabase/test-output.txt`. Se ejecutó el script reproducible sobre un contenedor nuevo sin red ni puertos, y se eliminó. El rol `authenticated` y RLS son reales; `auth.uid()` y `auth.users` se simulan exclusivamente en el bootstrap de pruebas. No son cuentas GoTrue reales.
- Compilación del núcleo, cliente URLSession y cola de sincronización mediante Swift Package Manager: aprobada.
- Sintaxis de las 12 fuentes de App con `swiftc -frontend -parse`: aprobada. No resuelve tipos ni disponibilidad de SwiftUI/Security/PhotosUI/Vision en los SDK de Apple.
- Tipado del coordinador `FamilyAppStore` con una adaptación temporal de AppStore sin SwiftUI y un sustituto de almacenamiento de sesiones: aprobado. Comprueba firmas y lógica Swift; **no comprueba el llavero real ni sustituye la compilación nativa**.
- Proyecto OpenStep, 12 referencias Swift existentes, XML del esquema y de los dos entitlements: comprobados. iOS utiliza un entitlement vacío; macOS solicita sandbox, archivos elegidos por el usuario y red saliente.
- Los cuatro SVG de Figma se parsearon y renderizaron localmente para inspección. El importador se probó con un contrato de API controlado: 4 frames, 110 textos nativos, Inter/Roboto y limpieza de una importación parcial. No se ejecutó en una cuenta Figma.

El pie del runner Swift Testing informa cero tests porque la suite usa XCTest. Los 78 casos ejecutados figuran en XCTest; no se cuenta el runner vacío como evidencia.

## Qué prueban las suites

Finanzas: céntimos exactos y límites, saldos iniciales y transferencias, edición/eliminación, meses Madrid con cambio de año/DST y febrero bisiesto, filtros, reservas/liberaciones/vencimientos/sobregasto, presupuestos históricos y permisos de mutación.

Datos: guardar antes de publicar en memoria, archivos corruptos conservados, validación de relaciones/UUID/versiones/importes, copias y confirmación, importación del prototipo sin inventar autoría, etiquetas buscables y compatibles con copias anteriores.

Avisos: formatos EUR, importes agrupados, varias cantidades/saldos/moneda extranjera, operaciones rechazadas/pendientes, códigos de seguridad, confirmación, reintentos/duplicados y ausencia del texto bancario en la copia financiera. No prueban OCR nativo.

Cliente familiar: configuración HTTPS y rechazo de claves privilegiadas, uso del JWT, endpoints/cuerpo de Auth y RPC, cambio de contraseña, cambio de cuenta prohibido en refresh, errores sin revelar contenidos privados. El transporte es controlado: no es una petición contra Supabase alojado.

Cola familiar: UUID/cuerpos inmutables, revisiones, orden de ACK, datos locales intactos ante conflicto, revocación, archivos corruptos, archivo antes de reemplazo, recuperación explícita conservando bytes originales, revisión desmesurada, copia local y atribuciones históricas.

PostgreSQL: aislamiento de hogares, cuentas confirmadas, invitación ligada a correo/caducidad/anulación/reintento, permisos por autor y administración, lista de miembros falsa sin privilegios, número JSON frente a cadenas/tipos desconocidos, controles Unicode, RLS incluso si se añadiera un SELECT, tombstones y no resurrección, confirmaciones perdidas, creación idempotente, revocación con reintentos, salida y último administrador, reinvitación sin recuperar automáticamente el rol antiguo, finanzas/reservas y una carrera concurrente real sin sobreasignación.

## Pendiente

- Compilar/ejecutar el código actual para macOS y simulador iPhone con Xcode. El entorno Linux no tiene SDK ni simuladores Apple. El script `Scripts/validate-apple.sh` detecta ese bloqueo y termina con error explícito.
- Probar formularios, cambio de modo local/familiar, selección/OCR de capturas, llavero real, varios windows, modo oscuro, Dynamic Type/VoiceOver, teclado, navegación y geometría del nuevo dashboard. El diseño Figma no demuestra la ejecución de SwiftUI.
- Crear un proyecto Supabase de usuario, aplicar su esquema, configurar cuentas y probar los JWT/Auth/correo reales. No se han creado cuentas, enviado correos reales ni subido datos financieros a un servicio.
- Ejecutar la matriz entre dos dispositivos/cuentas de `../../Supabase/LEEME.md`: invitación, autoría, actualización, desconexión/conflicto, ACK perdido y revocación.
- Publicación de la app, distribución y nueva publicación/restauración del snapshot cloud: no realizadas.

## Historial de comprobaciones

Las seis pruebas puras originales del prototipo pasaron sin modificar sus cuerpos, compilando su Finance.swift original en un paquete temporal. Las tres StoreTests originales que importan SwiftUI no se ejecutaron. La instalación de Swift y su script se verificaron previamente; no se ha reaplicado ni publicado la configuración del entorno durante este incremento.

## Prueba manual nativa mínima

1. Crear hogar local sin demo, Banco con 1.000 € y Efectivo con 0 €.
2. Ingreso de 2.000 €, gasto de 500 €: saldo 2.500 €, ingreso 2.000 €, gasto 500 €.
3. Reservar 600 €: sin reservar 1.900 €, gasto sigue en 500 €.
4. Transferir 300 €: total 2.500 €, Banco 2.200 €, Efectivo 300 €, informes sin inflación.
5. Editar/eliminar/cancelar, cerrar/reabrir; comprobar etiquetas y filtros. Presupuestos de meses distintos conservados.
6. Exportar/restaurar/cancelar y probar JSON corrupto. Comprobar separación demo y local.
7. Comprobar el resumen principal sin abrir Detalle: cifras importantes visibles a tamaño normal y ninguna franja sobre las pestañas. Con texto accesible grande debe poder desplazarse sin ocultar valores.
8. Pegar el ejemplo de AVISOS_BANCARIOS.md, y repetir con una captura ficticia. Revisar importe, categoría y etiquetas antes de guardar.
9. Configurar Supabase y seguir su matriz de dos cuentas antes de afirmar que el acceso familiar está validado.
