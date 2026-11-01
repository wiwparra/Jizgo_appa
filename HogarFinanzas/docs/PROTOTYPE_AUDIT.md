# Auditoría del prototipo 0.1

Recibido durante el desarrollo. El repositorio inicial estaba vacío; se inspeccionó el ZIP antes de integrar sus elementos. El original permanece intacto en los adjuntos.

SHA-256 del ZIP: `5c914b859eb868a525ba170f50043f676c3f5e8e074940c3c7339a48fe75157c`.

El prototipo incluye cuatro fuentes Swift, proyecto Xcode, esquema compartido, nueve pruebas XCTest y LEEME. No contiene AGENTS.md, credenciales ni transporte CloudKit. No se asumió que su documentación acreditara compilación.

Se conservaron o adaptaron estas decisiones válidas:

- Importes enteros y NumberFormatter español con Decimal para mostrar EUR.
- Saldo inicial separado de ingresos; reservas separadas de gastos.
- Fórmula mensual de metas, incluyendo los meses actual y final y redondeando hacia arriba al céntimo.
- Navegador de meses `MonthPicker`, adaptado como `PeriodPicker` con calendario explícito de Madrid y las etiquetas de accesibilidad originales.
- Patrón de copia candidata, escritura antes de publicar el cambio en memoria y bloqueo de edición al fallar la lectura.
- Edición/eliminación de metas y advertencia de reservas sin cobertura.
- Casos financieros y de recuperación originales, ampliados en las pruebas nuevas.

Las seis pruebas originales de `FinanceTests` se ejecutaron sin modificar sus cuerpos, en un paquete temporal que compila el `Finance.swift` original. Resultado: seis aprobadas. Las tres `StoreTests` originales dependen de SwiftUI y no se ejecutaron en Linux. El proyecto Xcode original tampoco se compiló.

Problemas corregidos en el nuevo código:

| Prototipo | Versión actual |
| --- | --- |
| Un saldo conjunto, sin cuentas ni transferencias | Cuentas con saldo inicial independiente y transferencias neutras en ingresos/gastos |
| Selector atribuido como «registrado por» | Autor separado del miembro atribuido; el importador no inventa autores |
| Presupuestos recurrentes que alteran meses pasados | Clave categoría/mes; cambios de un mes no alteran otros |
| Validación de JSON solo por versión y miembros | Validación estructural, de importes, relaciones, unicidad y límites |
| Solo exportación, sin restauración | Previsualización y confirmación de reemplazo, con validación completa |
| Sin notas ni filtros de cuenta/categoría | Notas, búsqueda y filtros combinables |
| Calendario del dispositivo | Calendario financiero de Madrid consistente entre dispositivos |
| Pestañas en todos los dispositivos | Barra lateral en Mac y pestañas en iPhone |

La nueva entrada monetaria admite coma decimal y rechaza puntos para evitar ambigüedad; permite cero/negativos solo donde el dominio lo admite (p. ej., saldo inicial). Los movimientos deben ser positivos. El límite por importe es 9 × 10¹² céntimos, con límites de cantidad de registros para evitar desbordamientos de agregados.

La migración es explícita desde JSON. Conserva UUID de movimientos, metas y miembros originales. Crea una cuenta conjunta para el saldo y los movimientos antiguos. Añade un propietario local de la importación; los nombres previos son atribuciones, no usuarios autenticados. El autor de cada movimiento antiguo queda `nil`; solo el administrador local puede corregirlo, sin cambiar su autoría desconocida. No se inventa historial de presupuestos: los límites se asignan al mes de importación. No se ejecuta una migración silenciosa ni se sobrescribe el archivo antiguo.
