# Rediseño de la app + "Ahora" (publicaciones que duran poco)

Fecha: 2026-11-07 · Repos: `Mobil_wuariekes` (Flutter) y `huarique_backend` (NestJS)
Bocetos aprobados: `.superpowers/brainstorm/11681-1794061129/content/app-rediseno.html` y `pantallas-ahora.html`

## Por qué

La app aún no está publicada. Hoy sirve para decidir a dónde ir; la de la competencia (video del 2026-11-06) hace que la gente la abra todos los días porque muestra "lo que pasa ahora". Queremos las dos cosas: el directorio de locales que ya tenemos y una capa de lo que pasa hoy cerca, con las promos de los negocios dentro. Para el negocio es un argumento de venta: "publica tu promo y te ve la gente que está cerca".

Éxito = la gente vuelve a la app aunque no esté buscando dónde comer, y los negocios publican promos.

## Metas

1. Rediseñar las pantallas principales según los bocetos (misma marca: rocoto `#C84B31`, ají `#ECB365`, hierba `#606C38`, crema `#FDFCF8`, café `#2D2424`).
2. Agregar "Ahora": publicaciones de usuarios + promos de negocios en el mapa, que vencen solas.

## No metas

- No hay comentarios en las publicaciones (solo reacciones).
- No hay publicaciones anónimas.
- No se cambia el modelo de puntos, niveles ni fidelización; solo cómo se ven.
- No hay app de iOS nueva ni cambios en la web en esta etapa.

## Anti-metas (si pasa esto, salió mal aunque funcione)

- Que alguien pueda publicar o confirmar algo desde un lugar donde no está.
- Que una publicación quede viva para siempre.
- Que una publicación de "solo amigos" la vea otra gente.
- Que se filtren datos privados de quien publica (email, teléfono): solo id, nickname/nombre y avatar.
- Que el check-in de restaurantes (que da puntos) se confunda con el ✅ de las publicaciones.

## Navegación nueva (decisión del usuario, aprobada en bocetos)

Barra de abajo: **Explorar · Actividad · ＋ · Premios · Perfil**.
- Favoritos sale de la barra y pasa a Perfil → "Guardados".
- Premios (hoy `my_loyalty_screen`, escondido en perfil) sube a la barra.
- El botón ＋ abre un menú: "Publicar lo que pasa aquí" y "Sugerir un lugar nuevo" (lo que hace hoy).

## Pantallas (según bocetos)

1. **Explorar**: mapa + lista deslizable abajo ("Cerca de ti · N") con tarjetas (foto, ⭐, categoría, distancia, "Desde S/", etiquetas Abierto y 🔥 promo). Buscador "¿Qué se te antoja?", avatar a la derecha. Interruptor **🍽️ Locales / ⚡ Ahora**. Chips: Todos, Abierto, Al paso, rubros. "Sorpréndeme" (hoy `discovery_screen`) se abre desde aquí.
   - En modo **Ahora**: franja "Hoy cerca de ti" arriba; pines 🔥 amarillos = promo de negocio, 📸/💬 verdes = publicación de gente; locales normales chicos.
2. **Ficha del local**: foto grande con carrusel, volver/guardar/compartir; nombre, ⭐, rubro, distrito, "Abierto hasta…"; acciones rápidas (Cómo llegar, WhatsApp, Reservar, Llamar — solo las que el local tenga); caja de promo del día; tarjeta de premios del usuario en ese local ("6/8 sellos"); pestañas Resumen · Carta · Fotos · Reseñas; botón fijo "📍 Estoy aquí · check-in" + 📷 subir foto/video sin reseña. La pestaña Carta solo si el local está reclamado (misma regla que la web).
3. **Check-in** (el de restaurantes, da puntos): estrellas, chips de opinión, "¿Qué pediste?", foto opcional, texto opcional, puntos visibles antes de publicar, aviso de sello sumado. Los puntos que se muestran son los reales del backend (hoy 10 + 5 con foto), no los del boceto. Los chips se guardan como texto al inicio del comentario, sin columna nueva. (Decisiones de Claude.)
4. **Actividad**: un feed que mezcla check-ins y publicaciones "Ahora" (con su contador de vida). Filtros (decisión de Claude):
   - **Siguiendo**: check-ins (`/checkins/feed/following`) + publicaciones de quienes sigo que puedo ver.
   - **Cerca de mí**: solo publicaciones "Ahora" cercanas (sin endpoint nuevo de check-ins).
   - **Amigos**: publicaciones de personas que me tienen en su lista de Amigos o que yo tengo en la mía, siempre respetando la visibilidad de cada publicación.
5. **Premios**: tarjetas de fidelización con sellos, distancia si está cerca, "¡Listo para canjear!", agregar a Wallet (si ya existe en la app; si no, se omite).
6. **Perfil**: avatar, nickname, bio; nivel, racha, check-ins; barra al siguiente nivel; insignias; lista: Mi mapa, Guardados, Mis amigos/seguidores, Mis publicaciones, Mensajes; ajustes ⚙️.
7. **Publicar** (Ahora): foto, video o texto; texto; "¿Quién lo ve?" 🌎 Todos · 👤 Seguidores · 👥 Amigos; aviso "Se publica donde estás (300 m) · dura 24 h"; botón "Publicar como @nick".
8. **Ver publicación**: media, autor, "quedan X h", texto, 👍 👎 ✅ con conteos, ✅ apagado si estás lejos ("Acércate para confirmar"), "Reportar".

## Reglas de "Ahora" (decididas por el usuario)

**Publicaciones de usuarios**
- Requiere sesión. Siempre muestra cuenta/nickname. Nunca anónimo.
- Tipo: foto, video corto o solo texto.
- Se publica en cualquier punto del mapa, pero **solo donde el usuario está**: la ubicación de la publicación es la del GPS del celular al publicar; el backend la valida (ver "Cerca").
- Vida base: **24 h** desde que se publica.
- Cada 👍 o ✅ suma **+1 h**; cada 👎 resta **1 h**. Tope total: **3 días** desde la publicación.
- Se oculta sola si 👎 − (👍 + ✅) ≥ 5. (Regla propuesta por Claude; el usuario la aceptó.)
- Visibilidad: **Todos**, **Seguidores** (quienes te siguen) o **Amigos** (lista que el autor arma a mano entre quienes lo siguen, como "Mejores amigos" de Instagram). Cualquiera puede seguir a cualquiera; la lista de Amigos es aparte.
- Ver: cualquiera (con o sin sesión para "Todos"), desde cualquier parte del mapa.
- Quién ve "Amigos": solo las personas que **el autor** puso en su lista. "Seguidores": quienes siguen al autor.
- La publicación no se liga a un local (sin `placeId`) en esta etapa. (Decisión de Claude.)
- 👍 y 👎: cualquiera con sesión, esté donde esté. Una reacción por usuario y publicación (puede cambiarla).
- ✅ ("confirmo que es cierto"): solo con sesión y a **≤ 300 m** de la publicación. No es el check-in de restaurantes y no da puntos.
- Sin comentarios.
- **Reportar**: con **3 reportes de usuarios distintos** la publicación se oculta para todos hasta que un admin la revise. Un usuario reporta una vez por publicación y como máximo 20 veces por día. (Decisión de Claude: con un solo reporte, una persona podría vaciar el mapa.)

**Promos de negocios**
- Salen de `Promotion` (ya existe: `startsAt`, `endsAt`, `isActive`, `placeId`; el dueño las crea en el panel).
- Viven lo que indicó el dueño. Si no tiene `endsAt`, en "Ahora" se muestra solo durante las **24 h** siguientes a `startsAt` (o a `createdAt` si tampoco tiene inicio).
- Esa regla de 24 h vale **solo para "Ahora"** (consulta propia). No se toca `PromotionsService` ni cómo se ven las promos en la ficha del local o en el panel. (Decisión de Claude.)
- Aparecen en el mapa "Ahora" y en la franja "Hoy cerca de ti", en la ubicación del local.
- **Solo de negocios que pagan un plan** (suscripción vigente de cualquier plan; decisión del usuario). Los locales sin plan no salen en "Ahora" aunque tengan promos. Es un argumento de venta: "con tu plan, tu promo aparece en el mapa de la gente que está cerca".
- No llevan 👍/👎/✅ en esta etapa (decisión de Claude: son del negocio, no de la comunidad).

**Cerca** = 300 m (decisión de Claude, ajustable con una constante). Se usa para publicar (la publicación queda en la posición del usuario) y para ✅. Validación en el backend comparando la posición enviada por el celular con la de la publicación (`ST_DWithin`). Ponytail: la posición la manda el celular y se puede falsear con GPS falso; aceptable en esta etapa.

## Backend (huarique_backend)

Lo que ya existe y se reusa: `UserFollow` (seguidores), PostGIS con `ST_DWithin` (búsqueda por distancia en `places.service`), subida a Cloudinary (`upload` y el patrón de `uploadPhoto`/`uploadVideo` con límites por hora), `Promotion`, feed de check-ins (`/checkins/feed`, `/checkins/feed/following`), `withPublicUser` para no exponer datos privados.

Nuevo (módulo propio, p. ej. `now`):
- Entidad publicación: autor, tipo (foto/video/texto), texto, url de media, ubicación (geography), visibilidad, `expiresAt`, contadores 👍/👎/✅, oculta (sí/no) y motivo, fechas.
- Entidad reacción: publicación, usuario, tipo (👍/👎/✅); única por usuario y publicación.
- Entidad lista de amigos: dueño, amigo.
- Entidad reporte: publicación, usuario, motivo.
- Endpoints:
  - Crear publicación (sesión; recibe lat/lng del celular; sube media).
  - Listar "Ahora" por zona del mapa (caja o centro+radio): devuelve publicaciones vigentes que el usuario puede ver + promos vigentes de locales en esa zona. Filtra por `expiresAt > ahora`, no oculta, y visibilidad.
  - Ver una publicación.
  - Reaccionar / quitar reacción (✅ exige lat/lng a ≤ 300 m). Recalcula `expiresAt` (respetando tope de 3 días) y la regla de ocultar por 👎.
  - Reportar.
  - Amigos: listar, agregar (solo entre mis seguidores), quitar.
  - Admin: ver reportadas, restaurar o borrar.
- Límite de **5 publicaciones por hora** por usuario para evitar spam (decisión del usuario).
- Las publicaciones vencidas no se borran al instante: dejan de listarse. Limpieza periódica opcional después.
- Feed de Actividad: mezclar check-ins + publicaciones (Siguiendo, Cerca, Amigos). Se puede resolver en la app pidiendo ambas listas y ordenando por fecha (decisión del builder).
- Migración SQL idempotente aplicada a mano en producción antes del despliegue (`migrationsRun: false`; esquema `wuarike_db`).

## Panel (warike_administrativo)

- Pantalla de admin para publicaciones reportadas (restaurar / borrar). Puede ser mínima.
- No cambia la creación de promos.

## Restricciones

- Congelamiento de funciones (plan de empresa 2026-11-04): el usuario decidió hacer esto igual porque la app aún no está publicada y "Ahora" ayuda a vender promos. Prioridad: no romper lo que ya funciona.
- La llave de Mapbox se pasa con `--dart-define-from-file=dart_defines.json`.
- Permisos de ubicación ya existen en la app (geocercas de fidelización); reusarlos.
- Moderación: el contenido es de terceros; Reportar debe funcionar desde el día 1.

## Lo que queda a criterio del builder

- Orden de las fases (sugerencia: 1) navegación y pantallas existentes rediseñadas; 2) backend "Ahora"; 3) pantallas "Ahora"; 4) panel de reportados).
- Cómo se cachean/refrescan los pines al mover el mapa.
- Duración máxima del video y tamaño de archivo (reusar los límites de `uploadVideo`).
- Detalles visuales finos que los bocetos no fijan.
