# Colaboración familiar: evaluación y trabajo pendiente

La aplicación actual es local. No usa un contenedor iCloud, no autentica cuentas Apple, no crea ni acepta CKShare, no transmite datos y no revoca acceso remoto. Activar iCloud en Xcode no implementa estas funciones. No se debe presentar esta entrega como colaboración familiar terminada.

## Fuentes oficiales consultadas

El 1 de noviembre de 2026 se descargaron y leyeron el README y ViewModel del [ejemplo oficial de Apple CloudKit Sharing](https://github.com/apple/sample-cloudkit-sharing). El código confirma la creación de CKShare, el acceso diferenciado a bases privada y compartida, y la aceptación de invitaciones entre cuentas independientes. Requiere Mac/Xcode, cuentas iCloud y un contenedor de un equipo Apple Developer.

En la revisión posterior para avisos y familia se pudo consultar la documentación oficial de Apple:

- [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users), mediante su recurso JSON oficial.
- [CKShare.ParticipantPermission](https://developer.apple.com/documentation/cloudkit/ckshare/participantpermission) y readWrite.
- [Comparación de membresías](https://developer.apple.com/support/compare-memberships/).

La ruta antigua con guiones bajos no era la URL vigente. La ruta con guiones responde correctamente con el acceso de red ya publicado. No se han cambiado de nuevo los ajustes del entorno.

El ejemplo de Core Data confirma dos almacenes (privado y compartido), invitaciones CKShare, aceptación, retirada de participantes y gestión de historial persistente. Advierte que la sincronización depende del sistema y no es en tiempo real. No se debe guardar un único JSON compartido con escrituras que sobrescriban todo el hogar.

En las capturas del usuario se utiliza un Personal Team. El usuario confirmó que solo dispone de cuenta gratuita. CloudKit no se puede habilitar con ese equipo. No se ha contratado ninguna membresía ni servicio. Todos los familiares confirmaron usar iPhone/Mac con cuentas iCloud independientes; el grupo En familia de Apple por sí solo no comparte estos registros. La decisión pendiente es si se prepara una alternativa de autenticación y datos con un servicio externo de plan gratuito, configurado por el usuario. No existe todavía ese backend ni una integración familiar funcional.

## Evaluación de Core Data con CloudKit

NSPersistentCloudKitContainer puede proporcionar persistencia local y transporte CloudKit. La colaboración entre cuentas requiere almacenes de ámbito privado y compartido, CKShare, aceptación en los ciclos de vida de iOS y macOS y gestión del propietario y participantes. Sincronización privada entre dispositivos del mismo Apple ID no cumple el acceso familiar.

Hay un problema adicional a validar antes de elegirlo: una compartición con permiso de escritura del conjunto no establece por sí sola la regla «cada miembro solo modifica sus movimientos». La validación en SwiftUI o en un repositorio local es útil, pero no es una barrera de autorización frente a otro cliente con las mismas credenciales. No se implementó una compartición de escritura global fingiendo que cumplía esos permisos.

Para satisfacer el requisito estricto hace falta definir y comprobar una autoridad que valide identidad y rol en cada mutación, o demostrar con documentación y pruebas una partición de datos/comparticiones que lo imponga de forma equivalente. No se ha contratado ni desplegado un backend. El contenedor y la firma son requisitos de integración, pero no sustituyen el trabajo de implementación que todavía falta.

## Componentes existentes y límites

`Ledger` comprueba miembros activos, administración de configuración, autoría inmutable y permisos de modificación/eliminación. `Entry.authorID` es distinto de `memberID`. `nil` significa autor histórico desconocido tras importar el prototipo; no se lo atribuye al importador. Los UUID locales no son credenciales.

`SyncReducer` es una función pura para una futura autoridad, con estos contratos probados:

- El adaptador autenticado debe derivar el actor de la sesión, nunca aceptar como prueba el UUID indicado por el cliente.
- Cada operación tiene UUID idempotente. Un reintento confirmado no duplica un movimiento. La pertenencia activa se verifica incluso en reintentos.
- Las ediciones y eliminaciones incluyen revisión esperada. Un conflicto se rechaza sin sobrescribir el estado: el cliente debe recargar y mostrar la diferencia al usuario.
- Las eliminaciones conservan tombstone y revisión; una escritura antigua no resucita el registro.
- Los identificadores aplicados y tombstones se exportan y restauran. No hay purga automática. El límite de operaciones obliga a diseñar checkpoint/retención antes de habilitar transporte a largo plazo.

Esto **no** incluye cola durable del cliente, autenticación, endpoint remoto, transporte, reconciliación de cuentas/metas/presupuestos ni serialización de reservas concurrentes. Un servidor futuro debe aplicar la mutación de reserva y la comprobación del saldo en una sola transacción; dos clientes desconectados no pueden garantizar cobertura global por sí solos. Deben mostrar reservas pendientes y resolver las rechazadas explícitamente.

`SyncStatus` define pendiente/sincronizando/sincronizado/error. La aplicación solo muestra `localOnly`: no se ha configurado un transporte. `UnconfiguredFamilyService` devuelve error al invitar o sincronizar. Sus pruebas demuestran que no se simula éxito; no prueban colaboración.

Revocar acceso debe retirar permisos remotos y bloquear nuevas operaciones. No puede borrar copias JSON o datos que el usuario ya haya exportado. Debe definirse y comprobarse la política de caché tras pérdida de acceso; no se promete borrado remoto de copias existentes.

## Intervención necesaria para la siguiente fase Apple

1. Usar un Mac con Xcode completo y ejecutar `Scripts/validate-apple.sh`. Corregir cualquier error de compilación que aparezca antes de afirmar compatibilidad.
2. Confirmar que existe un equipo Apple Developer apto para CloudKit. La documentación oficial ya pudo consultarse con la configuración publicada; no hace falta repetir ni publicar cambios de red para esta revisión.
3. Tras cerrar la arquitectura de autorización, seleccionar en Xcode un equipo Apple Developer, un bundle ID propio y crear su contenedor iCloud. Los identificadores son configuración; certificados, sesiones y credenciales se gestionan en Apple/Xcode y nunca se pegan en el código ni en el chat.
4. Implementar capacidades iCloud/CloudKit, notificaciones remotas, persistencia/sincronización e invitaciones con el contenedor real. El proyecto actual no solicita estas capacidades: habilitarlas sin el resto de código no proporcionaría colaboración.
5. Usar dos cuentas Apple independientes y dispositivos de prueba: iPhone A crea → Mac B recibe; edición sin conexión y conflicto concurrente; reintento tras caída antes de ACK; revocación durante desconexión; salida del hogar; rechazo de modificación de autor ajeno; aislamiento de hogares; invitación rechazada/caducada; error iCloud y recuperación sin pérdida local.

Esta matriz no se ha ejecutado. La colaboración sigue siendo funcionalidad pendiente, además de requerir configuración Apple.
