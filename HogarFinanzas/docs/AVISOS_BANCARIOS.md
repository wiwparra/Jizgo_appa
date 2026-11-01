# Avisos del banco y etiquetas

La aplicación no escucha, intercepta ni lee ventanas emergentes de otras apps. iOS no ofrece a Hogar Finanzas acceso a las notificaciones de la app bancaria. No se ha implementado una conexión bancaria ni un registro automático al llegar una notificación.

## Cómo registrar un aviso

1. Crea un hogar y al menos una cuenta manual.
2. Abre Resumen o Movimientos y pulsa **Desde aviso bancario** (icono de reconocimiento de texto).
3. Pega el texto, o pulsa **Seleccionar captura** y elige la imagen en Fotos. Cuando el banco solo muestra una ventana emergente, necesitas hacer la captura mientras sea visible y seleccionarla tú. La app no lo hará por su cuenta.
4. Si seleccionaste una imagen, espera al reconocimiento local y comprueba el texto. Pulsa **Preparar movimiento**.
5. Revisa el importe, concepto, tipo y fecha. Selecciona la cuenta correcta; nunca se adivina a partir de números bancarios. Elige categoría, miembro atribuido y etiquetas opcionales separadas por comas.
6. Consulta el texto original/reconocido desplegándolo en la hoja de revisión. La fecha inicial es hoy: cámbiala si el aviso corresponde a otro día.
7. Pulsa **Confirmar y registrar**. Cancelar no modifica las finanzas.

Si ya hay otro movimiento con igual cuenta, día, tipo e importe, aparece un aviso. Solo puedes crear otro después de revisar y marcar expresamente **Lo he revisado: es otro movimiento**. Es una advertencia heurística: no demuestra que dos operaciones sean idénticas y no detecta todos los duplicados. Reintentar la misma propuesta ya guardada no crea otra ni resucita una eliminada.

## Etiquetas

Ejemplos: `compra semanal, colegio, vacaciones`. Se admiten hasta 10 etiquetas por movimiento, con hasta 32 caracteres por etiqueta. Se eliminan duplicados ignorando mayúsculas y acentos, conservando el primer nombre introducido. Las etiquetas no sustituyen la categoría ni cambian el cálculo de presupuestos o saldos.

Pueden añadirse y editarse también en movimientos manuales. Se muestran en la lista, participan en la búsqueda y pueden filtrarse por etiqueta exacta. Las copias antiguas se abren con etiquetas vacías; las nuevas las incluyen. No restaures una copia nueva con una versión anterior de la app si necesitas conservar las etiquetas: la versión anterior no conoce ese campo.

## Interpretación conservadora

Solo se proponen importes acompañados por EUR o €. Se aceptan formatos como `12,50 EUR`, `1.234,56 €` y `€12.50`, siempre usando céntimos exactos. Números de tarjeta, fechas y códigos sin moneda no son importes.

- Si aparecen varias cantidades, aunque coincidan, no se elige una automáticamente. Así se evita tomar el saldo por el cargo.
- Si el único importe parece un saldo o aparece una moneda extranjera, se deja sin rellenar. No hay conversión de divisas.
- Si el tipo no es inequívoco, es una transferencia o parece pendiente/retención, se exige elegirlo. Las transferencias entre cuentas propias se registran con origen y destino.
- Se rechazan los textos que parecen contener claves/códigos de seguridad u operaciones rechazadas/canceladas.
- El concepto solo se sugiere cuando se identifica un texto tras «en». Puede estar incompleto o equivocado: hay que revisarlo.
- El OCR puede confundir caracteres. Todo campo es editable antes de confirmar. No verifica si el aviso es auténtico ni si la operación se liquidó realmente.

Para probar sin datos privados, pega: `Has realizado una compra de 12,50 EUR en CAFÉ CENTRAL con tu tarjeta terminada en 1234.` El resultado propuesto debe ser un gasto de 12,50 €, con cuenta por seleccionar. Pega también `Compra de 15,50 EUR. Saldo disponible 1200 EUR.`: el importe debe quedar vacío y pedir revisión.

## Datos y permisos

PhotosPicker da acceso a la imagen elegida por el usuario; la aplicación no solicita acceso general a toda la fototeca. Se admiten imágenes de hasta 15 MB y 32 millones de píxeles. Vision reconoce el texto en el dispositivo; no se añade un servicio remoto de OCR. La imagen y el texto quedan en memoria mientras se usa la hoja, y no se añaden al archivo del hogar ni a sus copias. Solo se guardan los campos que confirmes; no pegues datos bancarios sensibles en notas o conceptos si no deseas conservarlos.

La captura original continúa en Fotos, y puede estar sincronizada con iCloud Fotos según tus ajustes. Hogar Finanzas no la borra ni controla esa copia. No se registran imágenes, avisos o importes en logs.

## Validación pendiente

El dominio y la compatibilidad de datos tienen pruebas XCTest ejecutadas. La compilación SwiftUI/PhotosUI/Vision y su prueba en iPhone/Mac requieren Xcode y todavía no se han ejecutado en este entorno Linux. Esta versión requiere añadir también BankNoticeView.swift al target de la aplicación; el proyecto Xcode actualizado ya incluye la referencia.
