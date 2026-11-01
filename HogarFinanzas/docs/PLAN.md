# Plan de entrega y estado

1. Auditoría: repositorio inicialmente vacío; prototipo recibido después e inspeccionado. Sus seis pruebas puras pasan en Linux; reutilización y diferencias documentadas.
2. Dominio y persistencia: implementados y probados. 58 pruebas XCTest pasan con Swift 6.2.1.
3. Flujos nativos: fuentes SwiftUI y proyecto multiplataforma creados. Cuentas, movimientos, presupuestos, metas, copias e importación implementados. Sintaxis Swift comprobada; compilación y ejecución Apple pendientes.
4. Familia y sincronización: evaluación parcial de fuentes oficiales; permisos/reductor comprobados como componentes puros. Faltan autenticación, invitaciones, autoridad remota, cola duradera y transporte. No se presenta como funcionalidad terminada.
5. Validación Apple: falta un Mac con Xcode, ejecución de formularios y recuperación de errores, VoiceOver, tamaños de texto, teclado y caso familiar entre dos cuentas. Ver ICLOUD.md y VALIDATION.md.

6. Avisos y etiquetas: propuestas a partir de texto o captura seleccionada, OCR local con Vision, confirmación obligatoria y avisos de duplicados. Etiquetas compatibles con las copias anteriores. Dominio probado; PhotosPicker, OCR e interfaz pendientes de compilación/ejecución en Apple. Las ventanas emergentes de la app bancaria no pueden interceptarse.
