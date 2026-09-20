# Funciones trasladadas desde wuarikes_web

## Navegación y descubrimiento

- Explorar conserva el mapa, búsqueda, categorías, precios, radio, valoración, servicios y abierto ahora.
- La búsqueda incorpora distrito.
- «¿Dónde comemos?» abre recomendaciones por categoría, presupuesto, distrito y ubicación; permite pedir otras opciones.
- Listados de descubrimiento y restaurantes más guardados.
- Solicitud «Quiero Wuarikes aquí», con autenticación, validación y confirmación.
- La pestaña Actividad reemplaza la pantalla de mensajes vacía. La web de consumidores no ofrece conversaciones funcionales.

## Comunidad y cuenta

- Actividad general y de usuarios seguidos, con paginación, likes, compartir y acceso al perfil del autor.
- Perfil de otro usuario, seguir/dejar de seguir, seguidores y seguidos.
- Historial completo paginado; los likes del historial son informativos porque esa respuesta no incluye el estado personal del like.
- Perfil personal: nombre, biografía, ciudad, origen, pronombres, género, fecha de nacimiento, foto y portada.
- Privacidad: perfil público, favoritos visibles, mensajes de negocios y descubrimiento de usuarios.
- Sesiones: listar dispositivos, revocar una sesión ajena y cerrar las demás.
- Favoritos adaptados al contrato actual del backend; se actualizan al regresar del restaurante y muestran errores recuperables.
- Las pantallas principales se reconstruyen al cambiar de cuenta para no reutilizar información de otro usuario.

## Restaurantes

- Compartir el enlace público mediante la hoja nativa del sistema.
- «Quiero ir», contador e inversión de la selección persistida.
- «Estoy aquí» con ubicación obligatoria; permite indicar posteriormente el plato y precio.
- Reseñas con plato/precio y ubicación obligatoria según el backend actual.
- Carta por categorías, imágenes ampliables, ingredientes, alérgenos y disponibilidad.
- Promociones, platos más pedidos y distribución de valoraciones.
- Galería paginada de fotos y videos; imágenes ampliables y reproducción de video con pausa y desplazamiento temporal.
- Subidas a la galería para el propietario, como exige el backend: fotos hasta 10 MB, videos hasta 20 MB. Los demás usuarios aportan fotos mediante sus reseñas.
- Reseñas ordenables por fecha, mayor/menor puntuación y presencia de fotos; reseñas de Google.
- Etapa de confianza, amigos que visitaron, videos de TikTok, información ampliada, horarios, teléfono, sitio web y rutas.
- Sugerencias comunitarias de información desactualizada, conservando el proceso de validación del backend.

No se añadieron reclamación de restaurantes ni pantallas de edición directa de sus datos, por indicación del usuario. Las sugerencias comunitarias son un flujo independiente, igual que en la web.

## Enlaces y compilación

El usuario confirmó `https://wuarikes.com/`. Compartir y los enlaces legales usan ese dominio por defecto. Las páginas de términos, privacidad y libro de reclamaciones se abren en el navegador del dispositivo.

Se puede cambiar el dominio al compilar:

```powershell
flutter build apk --debug --dart-define=WEB_URL=https://wuarikes.com
```

`API_URL` conserva la configuración existente del backend.

## Verificación

- `flutter analyze --no-pub --no-fatal-infos`: sin errores ni advertencias; permanecen sugerencias de estilo del analizador.
- `flutter test --no-pub`: prueba de montaje existente y cuatro pruebas nuevas de contratos en `test/parity_test.dart`.
- `flutter build apk --debug --no-pub`: compilación Android.

Las pruebas de contratos usan HTTP simulado y no escriben datos en producción. No sustituyen una prueba en teléfono con cuentas reales para OAuth, ubicación, cámara/galería, permisos de propietario y revocación de sesiones. Tampoco se ha compilado iOS desde este entorno Windows.
