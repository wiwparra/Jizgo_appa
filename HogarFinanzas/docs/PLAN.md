# Estado de entrega

1. Prototipo 0.1 auditado e integrado. Sus seis pruebas puras originales pasaron en un paquete temporal; las tres que dependen de SwiftUI requieren Apple.
2. Dominio y persistencia: cuentas, transferencias, presupuestos mensuales, metas, reservas, copias/importación y etiquetas. Pruebas ejecutadas en Swift/Linux.
3. Avisos: propuestas desde texto o captura seleccionada, OCR local de Vision, revisión y confirmación. No se pueden interceptar notificaciones de la app bancaria. OCR/PhotosPicker pendientes de validación Apple.
4. Acceso familiar: cliente Supabase, sesiones en llavero, cuentas, invitaciones, roles/autores, cola persistente, conflictos/archivos conservados y autoridad PostgreSQL implementados. 78 tests Swift y 23 tests de PostgreSQL aprobados. Servicio alojado, correo y caso real entre dos cuentas aún sin configurar/probar.
5. Interfaz: franja inferior retirada, estado local en Hogar y copias, resumen compacto y detalle plegado. Sintaxis y tipado del coordinador comprobados; ejecución visual/accesibilidad y compilación completa pendientes de Apple.
6. Figma: paquete independiente con cuatro SVG y un importador local de 110 textos nativos, claro/oscuro para iPhone/Mac. XML, render visual y contrato de API verificados; ejecución final en Figma pendiente.

No se ha publicado la app ni se ha contratado/configurado un servicio externo. Siguiente intervención: crear el proyecto Supabase según Supabase/LEEME.md e instalar/validar la actualización con Xcode conservando identificador/equipo/datos. No se declara terminado el uso familiar ni la compatibilidad nativa antes de esas pruebas.
