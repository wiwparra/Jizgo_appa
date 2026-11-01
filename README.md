# Hogar Finanzas

Aplicación nativa SwiftUI para iPhone (iOS 17+) y Mac (macOS 14+), con núcleo Swift compartido, interfaz española y EUR. Incluye modo local y una integración familiar preparada para Supabase, que el usuario debe configurar.

**Estado:** 78 pruebas Swift y 23 pruebas de PostgreSQL aprobadas. El código nuevo todavía requiere compilación y ejecución Apple. No se ha activado un proyecto Supabase ni validado la colaboración entre dos cuentas/dispositivos reales. No se presenta como una aplicación terminada.

## Arranque y actualización

Abre [HogarFinanzas.xcodeproj](HogarFinanzas/HogarFinanzas.xcodeproj) en Xcode 16 o posterior. Selecciona el esquema HogarFinanzas y My Mac o un simulador. Para iPhone físico selecciona tu Team y un Bundle Identifier propio. El código familiar no necesita iCloud, App Groups ni Sign In with Apple.

Si ya tienes datos o firma configurada, sigue [ACTUALIZAR.md](HogarFinanzas/docs/ACTUALIZAR.md). La actualización añade fuentes, referencias de proyecto y entitlements por plataforma: no basta con copiar las tres vistas de una corrección anterior.

```sh
cd HogarFinanzas
./Scripts/test.sh
# Solo en un Mac con Xcode completo:
./Scripts/validate-apple.sh
```

Para el servidor, desde la raíz y con Docker local:

```sh
./Supabase/test.sh
```

Ese script crea PostgreSQL efímero sin red/puertos, prueba el SQL con roles reales y elimina su contenedor. No contacta con un proyecto alojado. Las pruebas de Auth usan un sustituto de `auth.uid()`: no validan GoTrue ni el correo real.

## Funciones

- Dashboard compacto: saldo total, reservas, saldo sin reservar e ingresos/gastos/resultado del mes. Cuentas, categorías y evolución se despliegan bajo Detalle. El estado de modo local está en Hogar y copias; no hay franja superpuesta a la navegación inferior. Con texto accesible grande se permite desplazamiento en vez de ocultar cifras.
- Cuentas manuales, saldos iniciales, ingresos/gastos y transferencias neutras en los informes. Crear/editar/eliminar, búsqueda y filtros por mes, cuenta, categoría, miembro y etiqueta.
- Etiquetas personalizadas, presupuestos históricos por mes, metas y reservas sin gastos ficticios. Se informa de reservas sin cobertura tras un gasto real.
- Propuestas desde texto o captura bancaria seleccionada, con OCR local, revisión y confirmación. [Uso y límites](HogarFinanzas/docs/AVISOS_BANCARIOS.md). iPhone no permite interceptar ventanas emergentes de la app del banco.
- Persistencia atómica, bloqueo de escritura ante lectura fallida, copias JSON confirmadas y migración explícita del prototipo. Demostración y datos reales separados.
- Acceso familiar por cuentas personales Supabase: invitaciones por correo confirmado/código, roles, permisos de autor y administración en PostgreSQL, cola sin conexión, ACK idempotente, conflictos conservados y revocación. [Configuración paso a paso](Supabase/LEEME.md).

La colaboración del código necesita un servicio configurado. Tener el grupo En familia de Apple no conecta los datos. La firma gratuita de Apple conserva sus límites/caducidad para instalar en cada dispositivo; Supabase no distribuye la app.

## Diseño editable en Figma

[Paquete Figma independiente](Design/HogarFinanzas-Dashboard-Figma.zip): iPhone/Mac en claro/oscuro, SVG y un importador que crea textos y capas nativos. [Instrucciones](Design/LEEME.md). Cambiar el diseño en Figma no cambia automáticamente el código.

## Protección y validación

Los importes usan céntimos exactos. Los JSON y archivos exportados contienen finanzas en claro. Las sesiones familiares van en el llavero; solo URL y clave pública publishable/anon van en preferencias. Nunca se incluye service_role, secreto JWT o contraseña PostgreSQL en la app. El servidor externo no tiene cifrado de extremo a extremo: su administrador/proveedor pueden acceder a sus datos según configuración.

No se han creado cuentas externas, contratado servicios, publicado la app, efectuado operaciones bancarias ni modificado/publicado de nuevo el entorno cloud. La preparación actual y sus limitaciones están en [VALIDATION.md](HogarFinanzas/docs/VALIDATION.md), [PLAN.md](HogarFinanzas/docs/PLAN.md) y la [auditoría del prototipo](HogarFinanzas/docs/PROTOTYPE_AUDIT.md).
