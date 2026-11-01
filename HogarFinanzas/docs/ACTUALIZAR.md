# Actualizar desde la versión anterior

Esta actualización incorpora BankNoticeView.swift, tres fuentes de acceso familiar y nuevas fuentes del paquete, además de entitlements separados para iOS y macOS. No basta con reemplazar solo las tres vistas que se cambiaron en la corrección anterior.

1. Si ya registraste datos, abre la app anterior y exporta una copia desde **Hogar y copias**. Guárdala en una ubicación privada: el JSON contiene los datos en claro.
2. En el Xcode anterior anota el **Team** seleccionado y el **Bundle Identifier exacto** de Signing & Capabilities. No hace falta compartir credenciales ni certificados.
3. Cierra Xcode. Conserva tu carpeta anterior como respaldo.
4. Descarga el ZIP nuevo y descomprímelo en otra carpeta. No sobrescribas la carpeta antigua.
5. Abre **HogarFinanzas → HogarFinanzas.xcodeproj** de la carpeta nueva. No abras Package.swift.
6. En **TARGETS → HogarFinanzas → Signing & Capabilities**, conserva **Automatically manage signing**, selecciona el mismo Team e introduce el mismo Bundle Identifier de tu instalación anterior en Debug y Release. El identificador por defecto del proyecto no es una sustitución del que ya configuraste.
7. No añadas **Sign In with Apple**, **iCloud** ni **App Groups**. La alternativa Supabase no necesita esas capacidades; su URL, clave pública y cuentas se configuran dentro de la app. El proyecto nuevo usa entitlements iOS vacíos y conserva red saliente/sandbox en Mac.
8. Selecciona tu iPhone y pulsa ▶︎. No borres la app anterior del teléfono para hacer la actualización: eso puede borrar su almacenamiento local.
9. Comprueba tus datos y etiquetas. Si aparece un hogar vacío, comprueba primero identificador/equipo y modo de demostración antes de registrar nada. Si necesitas restaurar, usa la copia exportada y confirma solo después de revisar el hogar de destino.

La compilación de las pantallas y de PhotosPicker/Vision debe verificarse en Xcode. Las pruebas ejecutadas en Linux comprueban el núcleo, el analizador, las etiquetas y las copias; no garantizan que la interfaz Apple compile sin nuevos ajustes.

Para activar el uso familiar sigue `Supabase/LEEME.md` desde la raíz de la descarga. Puedes seguir usando únicamente el modo local sin configurar ese servicio. Las copias se restauran en modo local; no sustituyen la autoridad compartida ni conceden acceso a un hogar. El diseño para Figma está separado en `Design/` y no cambia automáticamente el código.
