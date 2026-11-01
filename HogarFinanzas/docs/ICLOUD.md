# Decisión de acceso familiar

El usuario confirmó que todos usan Apple/iCloud, pero solo tiene un Personal Team gratuito. Se evaluó Core Data con CloudKit y compartición entre cuentas, consultando la documentación oficial y el ejemplo de Apple. Un contenedor privado sincronizado entre dispositivos del mismo Apple ID no sería acceso familiar.

Fuentes consultadas:

- [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users). La ruta con guiones es la vigente y pudo consultarse con la configuración de red ya publicada; la ruta antigua con guiones bajos devolvía 404.
- [CKShare.ParticipantPermission](https://developer.apple.com/documentation/cloudkit/ckshare/participantpermission), incluido readWrite.
- [Ejemplo oficial de Apple](https://github.com/apple/sample-cloudkit-sharing).
- [Comparación de membresías](https://developer.apple.com/support/compare-memberships/).

Core Data/CloudKit utiliza almacenes privados y compartidos, CKShare e invitaciones. La sincronización depende del sistema y no es instantánea. Una compartición de escritura del conjunto no impone por sí sola «cada miembro solo modifica sus movimientos». Esas reglas no se pueden presentar como garantizadas solo por ocultar botones.

Con la cuenta actual no se activa CloudKit. El usuario autorizó preparar una alternativa externa gratuita que configurará personalmente: **Supabase**. La implementación añade autenticación por correo/contraseña y una autoridad PostgreSQL que deriva el usuario de `auth.uid()`, aplica permisos por hogar/autor y serializa las reservas.

No se han creado ni contratado servicios. El [procedimiento Supabase](../../Supabase/LEEME.md) detalla URL/clave pública, cuentas, límites de correo, configuración y pruebas entre dos dispositivos pendientes. Esta alternativa no necesita los permisos iCloud ni Sign In with Apple; no se han añadido al proyecto.

El rol de administrador del hogar no concede acceso al panel del proyecto Supabase. A la inversa, el administrador del proyecto de datos puede acceder a su base de datos; no hay cifrado de extremo a extremo. Las copias exportadas o datos descargados no pueden borrarse a distancia al revocar acceso.

`SyncReducer` y `UnconfiguredFamilyService` se mantienen como componentes puros del núcleo y compatibilidad de pruebas. La nueva integración usa `SupabaseClient`, `FamilyWorkspace`, `FamilyAppStore` y `Supabase/schema.sql`; probar los reductores por sí solos no equivale a validar esa integración en vivo.
