# Preparar el hogar familiar sin Apple Developer de pago

Esta entrega incluye el cliente Swift, las pantallas y la autoridad PostgreSQL. **No hemos creado ni activado un proyecto Supabase, ni validado dos dispositivos con cuentas reales.** Los tests locales se detallan al final. Configurar el servicio y ejecutar las pruebas Apple son pasos pendientes.

El servicio externo es Supabase. Debes elegir y configurar tú su plan gratuito: este código no crea cuentas, no pide tarjeta, no cambia planes y no contrata servicios. Consulta sus condiciones y cuotas actuales; el plan gratuito puede limitar o pausar proyectos. Los datos que decidas compartir saldrán del dispositivo y se guardarán en ese proyecto.

## 1. Crear tu proyecto

1. En el navegador, entra en https://supabase.com/dashboard y crea tu cuenta si no tienes una.
2. Crea un **proyecto nuevo y dedicado** a Hogar Finanzas dentro del plan gratuito. Elige una región apropiada para ti y guarda la contraseña de base de datos de forma privada. No se introduce en la app ni se envía por chat.
3. Espera a que termine de prepararse.
4. En tu descarga del código, abre `Supabase/schema.sql` con un editor de texto, selecciona todo y copia.
5. En Supabase, abre **SQL Editor**, crea una consulta nueva, pega ese contenido y pulsa **Run**.
6. Si termina con error, conserva el mensaje para revisarlo. No borres tablas ni esquemas para reintentarlo. El script es para instalación inicial, está dentro de una transacción y no se debe ejecutar como una actualización sobre datos existentes.

No ejecutes `tests/bootstrap.sql` en Supabase: es una imitación mínima de Auth solo para el contenedor de pruebas. El proyecto real ya proporciona `auth.users`, `auth.uid()` y los roles.

El esquema financiero permanece privado, con RLS habilitado y sin acceso directo desde las cuentas de la app. Solo se exponen los RPC que verifican la sesión y el rol. No tienes que publicar ni añadir `hogar_private` a los esquemas expuestos por la API.

## 2. Preparar las cuentas de los familiares

Cada persona necesita su propio correo y contraseña. No hay contraseña familiar compartida y no se usan nombres como autenticación.

El correo integrado de Supabase tiene restricciones: sin un SMTP propio, puede rechazar direcciones que no sean del equipo del proyecto y tiene cuotas reducidas. No es un proveedor general de correo gratuito para tus familiares.

Para empezar sin contratar correo:

1. Abre **Authentication → Users → Add user → Create user**, o la opción equivalente de tu panel.
2. Crea una cuenta para cada persona con su correo real y una contraseña inicial distinta. Si se ofrece **Auto Confirm User**, actívalo para esa cuenta creada administrativamente. Comprueba que su correo figure confirmado; la autoridad financiera lo exige.
3. Entrega las credenciales iniciales por una vía privada. No las pongas en el repositorio, capturas de soporte o este chat.
4. Cada persona debe entrar después en **Acceso familiar → Contraseña personal** y establecer su propia contraseña de al menos 12 caracteres.

No hace falta añadir a tus familiares al equipo administrativo de Supabase. Eso les daría acceso al panel y no equivale al rol de miembro de la app.

Mantén activada la confirmación de correo en Auth. Si prefieres que cada persona use **Crear cuenta** desde la app, configura antes un SMTP que ya tengas o el que decidas contratar por tu cuenta. La app muestra el aviso para confirmar el correo y no permite trabajar en el servidor con una cuenta sin confirmar. No se ha contratado correo ni enviado mensajes reales durante este desarrollo.

La app permite cambiar una contraseña estando conectado. No incluye un flujo propio de recuperación por correo: para recuperar acceso hay que usar las opciones administrativas de Supabase o configurar su correo correctamente.

## 3. Obtener los dos datos públicos de configuración

Busca **Project URL** y **API Keys** en los ajustes/API de tu proyecto:

- URL con formato `https://identificadordelproyecto.supabase.co`.
- **Publishable key**, que empieza por `sb_publishable_`. Si tu proyecto conserva las claves antiguas, se acepta la clave **anon/public** de rol `anon`.

Nunca utilices **secret key**, **service_role**, la contraseña PostgreSQL ni el secreto JWT en la app. No deben enviarse al chat. El cliente rechaza los tipos de clave privilegiados que reconoce.

La URL y la clave pública serán las mismas para todos los familiares; sus cuentas y sesiones serán diferentes. Tener esa clave pública no concede acceso financiero: los RPC requieren JWT de una cuenta autorizada.

No es necesario cambiar la configuración de red del entorno Codex para usar la app en tu iPhone. Si más adelante quieres probar el servicio remoto desde Codex, necesitaremos autorizar el hostname exacto de tu proyecto; no se ha añadido un comodín ni configurado credenciales aquí.

## 4. Abrir tu primer hogar compartido

1. Actualiza la app según `HogarFinanzas/docs/ACTUALIZAR.md`. Conserva el mismo Team y Bundle Identifier de tu instalación.
2. Abre **Hogar y copias → Configurar o gestionar mi hogar familiar**. También se puede acceder desde la bienvenida.
3. Introduce la URL, la clave pública y tu correo/contraseña, y pulsa **Iniciar sesión**.
4. En **Crear hogar familiar nuevo**, introduce tu nombre visible y el del hogar. Pulsa **Crear hogar compartido**. Serás administrador.
5. Si quieres empezar desde cero, añade cuentas y movimientos como antes. Si quieres compartir tus datos locales previos, utiliza **Copiar mi hogar local a este hogar vacío** y confirma la subida.

La copia local previa no se borra. Al copiar, se conservan cuentas, presupuestos, metas y movimientos vigentes. Los nombres locales no pueden convertirse en usuarios verificados: la atribución anterior se conserva en notas, la atribución actual se asigna al importador y el autor histórico queda sin verificar. Los tombstones previos siguen en la copia local; no se publican como nuevos movimientos eliminados.

Un hogar compartido vacío no admite estrenar reservas por encima de su saldo. Si tu copia local ya tenía reservas sin cobertura, debes revisarlas antes de copiar; el rechazo conserva tus archivos y la propuesta pendiente. No se oculta ningún gasto ni se altera silenciosamente la copia original.

Las creaciones de hogar se guardan con UUID antes de enviar: al reintentar una respuesta perdida se recupera el mismo hogar. Si había una creación pendiente, se conserva su nombre original hasta completarla.

## 5. Invitar y entrar desde otro dispositivo

1. Como administrador, ve a **Acceso familiar → Invitar familiar** y escribe el correo exacto de la cuenta confirmada de esa persona.
2. Pulsa **Crear invitación** y **Compartir código**, o copia el código. Caduca en siete días y está ligado a ese correo. Crea una invitación para cada familiar; un código único no sirve para todo un grupo de correos diferentes.
3. La otra persona abre su app, configura la misma URL y clave pública e inicia sesión con su propia cuenta.
4. En **Aceptar invitación**, escribe su nombre visible y pega el código. Pulsa **Aceptar y abrir hogar**.
5. Registrad un movimiento de prueba y comprobad que aparece en ambos dispositivos. La app sincroniza al abrirse/activarse, cada 30 segundos mientras está activa, o al pulsar **Actualizar/Sincronizar ahora**. No es sincronización inmediata garantizada ni un servicio permanente en segundo plano.

La app debe estar instalada en cada dispositivo mediante Xcode, como hasta ahora. Se mantienen la caducidad y los límites de instalación de la firma gratuita. Supabase comparte datos; no instala la aplicación ni la publica en App Store. Si cada persona utiliza un Personal Team distinto, puede necesitar un Bundle Identifier propio: eso no impide que use el mismo proyecto de datos.

## 6. Permisos, desconexión y conflictos

- Todos los miembros activos pueden leer el hogar.
- Cada usuario crea movimientos con su identidad autenticada, aunque los atribuya a otro miembro activo.
- Cada miembro solo modifica/elimina sus propios movimientos. Un administrador puede gestionar todos, incluidos los históricos de miembros que ya salieron. El autor no se cambia al editar.
- Solo administradores gestionan cuentas, presupuestos, metas y miembros. Se puede promover a otro miembro; el último administrador no puede salir o quitarse el rol sin dejar otro activo.
- Las invitaciones pueden anularse. Revocar un miembro bloquea sus nuevas lecturas, escrituras y reintentos de operaciones previamente confirmadas. Una nueva invitación no restaura automáticamente un antiguo rol de administrador.

Los cambios sin conexión se guardan atómicamente con una cola persistente. Hay un límite de 100 cambios y 64 MB de archivo local; cada propuesta compartida admite hasta 16 MB. Al llegar al límite se rechazan nuevas modificaciones sin alterar lo ya guardado y se pide sincronizar/resolver.

La política inicial es conservadora: una revisión para todo el hogar. Si otra persona cambia cualquier parte entre tu lectura y tu envío, no se mezclan ni sobrescriben automáticamente las propuestas. El servidor rechaza la revisión antigua. También se mantienen las propuestas rechazadas por validación o cambios de permisos.

En **Acceso familiar → Revisar conflicto**, compara los movimientos y conserva una copia antes de decidir. **Archivar mis cambios y cargar los compartidos** guarda tanto la cola íntegra como una copia financiera de tu estado visible; después descarga el estado aceptado. La cola archivada no se reenvía automáticamente. Puedes exportar la copia y restaurarla en modo local para revisar lo que falte y volver a introducir los cambios autorizados. No existe un botón de sobrescribir por fuerza.

La eliminación usa tombstones y aumenta la revisión del movimiento. Los reintentos mantienen el UUID y el cuerpo; un ACK perdido no duplica el cargo. La comprobación de saldo/reservas y la escritura se hacen con bloqueo de la misma fila en una transacción de PostgreSQL: dos clientes no pueden reservar la misma cobertura global por separado. Los gastos posteriores pueden dejar reservas sin cobertura y se conservan.

Ante una caché ilegible se bloquea la edición. La recuperación requiere una sesión y lectura remota válidas, confirmación y conservación previa del archivo ilegible. Los cambios que nunca llegaron al servidor podrían necesitar recuperación manual; no se promete reconstruir un archivo corrupto. Una lectura fallida nunca sustituye el hogar por uno vacío.

Cerrar sesión o volver al modo local no borra la cola de cada cuenta/hogar. Al volver a entrar con la misma cuenta se recupera; no se carga una cola ajena como si perteneciera al nuevo usuario. La caché se separa por proyecto, cuenta y hogar.

Tras una revocación, los datos ya descargados permanecen como copia local y las modificaciones quedan bloqueadas cuando se conoce la revocación. No se puede borrar a distancia un JSON que alguien ya exportó ni asegurar el borrado de copias. La autoridad remota comprueba la pertenencia activa en cada petición, sin confiar solo en el rol que indique el cliente.

## 7. Protección real y comprobaciones pendientes

Las sesiones se guardan en el llavero del dispositivo, accesibles con el dispositivo desbloqueado y sin migración a otro dispositivo mediante el llavero. No se guardan contraseñas en archivos ni código. La configuración pública se guarda en preferencias. El transporte usa HTTPS con verificación TLS normal.

El archivo financiero y la cola usan escritura atómica, protección completa en iOS y permisos 0600. macOS conserva sandbox y permiso de red saliente; iOS usa un entitlement vacío, sin iCloud, App Groups ni Sign In with Apple.

No hay cifrado de extremo a extremo. El administrador del proyecto Supabase y el proveedor pueden acceder a los datos del servidor según su configuración. Las copias JSON exportadas contienen finanzas en claro. No se registran contenidos financieros ni credenciales en logs de la app; debes gestionar aparte los ajustes y retención de logs del servicio.

Pruebas ejecutadas: núcleo/cola/cliente con transporte controlado en Swift, y autoridad/RLS/transacciones en PostgreSQL real aislado, con `auth.uid()` simulado. No equivalen a ejecutar GoTrue real, confirmar correos ni probar dos cuentas desde Apple. No se creó un servicio alojado ni se enviaron datos reales. Compilación SwiftUI/Security/PhotosUI/Vision y la matriz entre dos dispositivos siguen pendientes.

Comandos de desarrollo:

```sh
cd HogarFinanzas
./Scripts/test.sh
# Desde la raíz del repositorio, con Docker local:
./Supabase/test.sh
```

El script PostgreSQL crea su contenedor sin red ni puertos, aplica el esquema, ejecuta los tests y elimina solo ese contenedor. `POSTGRES_HOST_AUTH_METHOD=trust` se usa exclusivamente dentro de ese contenedor aislado; no es configuración para el servicio real.

Referencias oficiales consultadas: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [passwords](https://supabase.com/docs/guides/auth/passwords), [límites SMTP](https://supabase.com/docs/guides/auth/auth-smtp). Antes de utilizar datos reales, completa la siguiente matriz con datos ficticios.

### Aceptación entre dos cuentas reales (pendiente)

- A crea hogar, invita al correo de B, B acepta; un correo C no puede usar el código.
- A crea en iPhone, B ve en Mac. B atribuye un movimiento a A y el autor sigue siendo B.
- B no puede editar un movimiento de A ni cambiar su rol mediante una llamada directa.
- Sin conexión B crea/edita; vuelve a conectarse; el cambio aparece una vez. Si ambos editaron el hogar, aparece conflicto sin pérdida silenciosa.
- Se pierde la respuesta de un envío: repetir el mismo UUID no duplica ni resucita eliminados.
- A revoca a B mientras B está desconectado. B ya no puede leer ni enviar cambios nuevos al recuperar conexión. Sus copias previas siguen la política descrita.
- Dos administradores intentan reservar cobertura concurrentemente; solo una propuesta de la misma revisión es aceptada.
- Cancelar/salir/cambiar de cuenta conserva o archiva las colas correctas; no mezcla datos entre hogares.
- Exportar/restaurar funciona en modo local; una copia no concede membresía ni sustituye la autoridad compartida.
