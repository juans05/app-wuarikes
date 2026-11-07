# Rediseño de la app + "Ahora" — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rediseñar la app Flutter de Wuarikes y agregar "Ahora": publicaciones de usuarios que vencen solas y promos de negocios con plan pagado, en el mapa.

**Architecture:** El backend (NestJS) suma un módulo `now`: 4 tablas nuevas, reglas puras en `now-rules.ts` y endpoints REST. El panel (Next.js) suma una sección de moderación para las publicaciones reportadas. La app (Flutter) suma modelos y llamadas de `now`, una barra de navegación nueva y las pantallas de los bocetos.

**Tech Stack:** NestJS + TypeORM + PostgreSQL/PostGIS (`wuarike_db`), Jest · Next.js 14 (panel) · Flutter 3 / Dart, `provider`, `http`, `flutter_map`, `flutter_test`.

**Spec:** `Mobil_wuariekes/docs/superpowers/specs/2026-11-07-rediseno-app-ahora-design.md`. Bocetos: `Mobil_wuariekes/.superpowers/brainstorm/11681-1794061129/content/app-rediseno.html` y `pantallas-ahora.html`.

## Global Constraints

- **Ramas:**
  - backend `feat/ahora`, a partir de `origin/main`;
  - panel `feat/ahora-moderacion`, a partir de `origin/main`;
  - app `feat/rediseno-ahora`, a partir de `main`.
  - Nada se fusiona a main ni se sube sin permiso del usuario.
- **Commits:** terminan con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Marca:**
  - colores: rocoto `#C84B31`, ají `#ECB365`, hierba `#606C38`, crema `#FDFCF8`, café `#2D2424`;
  - en la app, todo color sale de `AppColors` en `lib/core/app_theme.dart`.
- **Base de datos:**
  - las tablas viven en el esquema `wuarike_db`;
  - la migración es un `.sql` idempotente en `huarique_backend/migrations/`;
  - el despliegue no corre migraciones (`migrationsRun: false`): el SQL se aplica a mano en producción antes de desplegar, y solo con aprobación del usuario.
- **Reglas "Ahora"** (copiadas tal cual del spec):
  - **Vida:**
    - base de 24 h;
    - cada 👍 o ✅ suma +1 h y cada 👎 resta 1 h;
    - tope de 3 días (72 h) desde que se publica.
  - **Se oculta:**
    - por votos, si 👎 − (👍 + ✅) ≥ 5;
    - por reportes, con 3 reportes de usuarios distintos.
  - **Cerca:** 300 m. Se usa para dar ✅ y para fijar la ubicación al publicar: la del GPS del celular.
  - **Límites de publicar y reportar:**
    - 5 publicaciones por hora por usuario;
    - 1 reporte por usuario y publicación, y 20 reportes por día por usuario.
  - **Visibilidad:**
    - `all` (Todos);
    - `followers` (quienes siguen al autor);
    - `friends` (solo quienes el autor puso en su lista).
  - **Sin anónimos:** se muestra la cuenta o el nickname del autor.
  - **Sin comentarios.**
  - **Sin `placeId`:** las publicaciones no se ligan a un local en esta etapa.
  - **Promos:**
    - solo de locales con una suscripción `status = 'active'`;
    - duran hasta `endsAt`; si no tiene, 24 h desde `startsAt` (o desde `createdAt` si tampoco tiene inicio);
    - esta regla vale solo dentro de "Ahora": no se toca `PromotionsService`.
- **Datos del autor que se exponen:** solo `id`, `fullName` y `avatarUrl`. Se reusa `withPublicUser` de `src/modules/places/places.service.ts`.
- **Check-in de restaurantes:**
  - es distinto del ✅ y no cambia cómo se ganan los puntos;
  - la pantalla muestra los puntos reales (10, más 5 con foto);
  - los chips de opinión se guardan como texto al inicio del comentario.
- **Mapbox:** la app se corre con `flutter run --dart-define-from-file=dart_defines.json`.

## Review Focus

1. **Posición falsa o ausente:** si se publica sin lat/lng, o con lat/lng fuera de rango, se rechaza con 400. Una ✅ sin lat/lng también se rechaza con 400.
2. **Publicación vencida u oculta abierta por enlace directo:** `GET /now/posts/:id` responde 404, nunca la muestra.
3. **Reaccionar dos veces o cambiar de reacción:** queda una sola reacción por usuario, y los contadores no se duplican ni quedan negativos.
4. **Visibilidad `friends`:** un seguidor que no está en la lista del autor no la ve en `/now`, `/now/feed` ni `/now/posts/:id`.
5. **Mapa sin conexión, o el backend responde 500:** la capa "Ahora" muestra un aviso y el mapa de locales sigue funcionando.

---

## Fase 1 · Backend (`huarique_backend`, rama `feat/ahora`)

### Task 1: Reglas puras y tablas

**Files:**
- Create:
  - `src/modules/now/now-rules.ts`
  - `src/modules/now/entities/now-post.entity.ts`
  - `src/modules/now/entities/now-reaction.entity.ts`
  - `src/modules/now/entities/now-friend.entity.ts`
  - `src/modules/now/entities/now-report.entity.ts`
  - `migrations/add_now_tables.sql`
- Test: `src/modules/now/now-rules.spec.ts`

**Interfaces:**
- Produces, en `now-rules.ts`:
  - constantes `NOW_RADIUS_M = 300`, `BASE_HOURS = 24`, `MAX_HOURS = 72`, `HIDE_MARGIN = 5`, `REPORTS_TO_HIDE = 3`, `POSTS_PER_HOUR = 5`, `REPORTS_PER_DAY = 20`, `PROMO_DEFAULT_HOURS = 24`;
  - `computeExpiresAt(createdAt: Date, likes: number, dislikes: number, checks: number): Date`;
  - `shouldHideByVotes(likes: number, dislikes: number, checks: number): boolean`;
  - `promoVisibleUntil(p: { startsAt: Date | null; endsAt: Date | null; createdAt: Date }): Date`;
  - `type NowVisibility = 'all' | 'followers' | 'friends'` y `canSee(visibility: NowVisibility, authorId: string, viewerId: string | null, viewerFollowsAuthor: boolean, viewerInAuthorFriends: boolean): boolean`.
- Produces, las entidades:
  - **`NowPost`** (tabla `now_posts`): `id` uuid, `authorId` (`author_id`, con relación `author` a `User`), `kind` (`'photo' | 'video' | 'text'`), `text` (varchar 500, puede ser nulo), `mediaUrl`, `location` (geography Point 4326), `latitude`, `longitude`, `visibility`, `likes`, `dislikes`, `checks`, `reports` (int, por defecto 0), `hidden` (bool), `hiddenReason`, `expiresAt`, `createdAt`.
  - **`NowReaction`** (tabla `now_reactions`): `postId`, `userId`, `type` (`'like' | 'dislike' | 'check'`), única por `(postId, userId)`.
  - **`NowFriend`** (tabla `now_friends`): `ownerId`, `friendId`, única por el par.
  - **`NowReport`** (tabla `now_reports`): `postId`, `userId`, `reason`, `createdAt`, única por `(postId, userId)`.

- [ ] **Step 1: Escribir los tests que fallan**

```ts
describe('now-rules', () => {
  const t0 = new Date('2026-11-07T12:00:00Z');
  const h = (n: number) => new Date(t0.getTime() + n * 3600_000);
  it('base 24 h', () => expect(computeExpiresAt(t0, 0, 0, 0)).toEqual(h(24)));
  it('👍 y ✅ suman, 👎 resta', () => expect(computeExpiresAt(t0, 3, 1, 2)).toEqual(h(28)));
  it('tope 72 h', () => expect(computeExpiresAt(t0, 500, 0, 0)).toEqual(h(72)));
  it('nunca antes de publicarse', () => expect(computeExpiresAt(t0, 0, 99, 0)).toEqual(t0));
  it('oculta con margen 5', () => {
    expect(shouldHideByVotes(1, 6, 0)).toBe(true);
    expect(shouldHideByVotes(1, 5, 0)).toBe(false);
  });
  it('promo usa endsAt', () => expect(promoVisibleUntil({ startsAt: null, endsAt: h(5), createdAt: t0 })).toEqual(h(5)));
  it('promo sin fin: 24 h desde inicio', () => expect(promoVisibleUntil({ startsAt: h(2), endsAt: null, createdAt: t0 })).toEqual(h(26)));
  it('promo sin fechas: 24 h desde creada', () => expect(promoVisibleUntil({ startsAt: null, endsAt: null, createdAt: t0 })).toEqual(h(24)));
  it('friends solo para la lista', () => {
    expect(canSee('friends', 'a', 'b', true, false)).toBe(false);
    expect(canSee('friends', 'a', 'b', false, true)).toBe(true);
    expect(canSee('followers', 'a', 'b', true, false)).toBe(true);
    expect(canSee('followers', 'a', null, false, false)).toBe(false);
    expect(canSee('all', 'a', null, false, false)).toBe(true);
    expect(canSee('friends', 'a', 'a', false, false)).toBe(true); // el autor siempre ve lo suyo
  });
});
```

- [ ] **Step 2: Correr y ver que falla:** `npx jest src/modules/now/now-rules.spec.ts`. Falla con "Cannot find module './now-rules'".
- [ ] **Step 3: Implementar `now-rules.ts`** con las firmas de arriba.
- [ ] **Step 4: Crear las 4 entidades** con nombres de columna en snake_case, siguiendo `user-follow.entity.ts` y la columna `location` de `place.entity.ts`.
- [ ] **Step 5: Escribir `migrations/add_now_tables.sql`.** Usa `CREATE TABLE IF NOT EXISTS wuarike_db.now_*` y índices `IF NOT EXISTS`:
  - GIST sobre `now_posts.location`;
  - `(expires_at)` en `now_posts`;
  - las restricciones únicas.
- [ ] **Step 6: Correr la prueba y la compilación:** `npx jest src/modules/now/now-rules.spec.ts` y `npx tsc --noEmit -p .`. La prueba pasa (PASS) y la compilación no da errores.
- [ ] **Step 7: Commit** con el mensaje `feat(now): reglas y tablas de publicaciones Ahora`.

### Task 2: Crear, listar y ver publicaciones; promos de locales con plan

**Files:**
- Create:
  - `src/modules/now/now.service.ts`
  - `src/modules/now/now.controller.ts`
  - `src/modules/now/now.module.ts`
  - `src/modules/now/dto/create-now-post.dto.ts`
  - `src/modules/now/dto/now-area.dto.ts`
  - `src/modules/auth/guards/optional-jwt-auth.guard.ts`, solo si no hay uno equivalente (buscar antes con grep "handleRequest")
- Modify: `src/app.module.ts`, agregando `NowModule` a `imports`
- Test: `src/modules/now/now.service.spec.ts`

**Interfaces:**
- Consumes: `now-rules.ts` y las entidades de la Task 1; `withPublicUser` (`places.service.ts`); el patrón de Cloudinary de `uploadPhoto`/`uploadVideo` en `places.controller.ts` (fotos `jpg|jpeg|png|webp` hasta 10 MB y videos `mp4|mov` hasta 20 MB); `Subscription.status === 'active'` por `placeId`.
- Produces (los usan la Task 3 y la app):
  - **`GET /api/now?minLat&minLng&maxLat&maxLng`**, sesión opcional:
    - responde `{ posts: NowPostDto[], promos: NowPromoDto[] }`;
    - `NowPostDto = { id, kind, text, mediaUrl, latitude, longitude, visibility, likes, dislikes, checks, expiresAt, createdAt, author: { id, fullName, avatarUrl }, myReaction: 'like' | 'dislike' | 'check' | null }`;
    - `NowPromoDto = { id, title, description, imageUrl, discountType, discountValue, visibleUntil, place: { id, name, latitude, longitude, coverImageUrl } }`.
  - **`GET /api/now/posts/:id`**, sesión opcional: responde `NowPostDto`, o 404 si está vencida, oculta o no visible.
  - **`POST /api/now/posts`**, con sesión, multipart:
    - campo `file` opcional;
    - campos `kind`, `text`, `visibility`, `latitude`, `longitude`;
    - responde `NowPostDto`;
    - `@Throttle({ default: { ttl: 3_600_000, limit: 5 } })`.
  - `NowService.isFollower(viewerId, authorId): Promise<boolean>` y `NowService.inFriends(ownerId, friendId): Promise<boolean>`.

- [ ] **Step 1: Escribir los tests que fallan.** Usan repositorios simulados con `jest.fn()`, como en `business-places.controller.spec.ts`.
  - `create rechaza sin latitude/longitude (BadRequestException)`.
  - `create rechaza kind=text sin texto, y kind=photo|video sin archivo`.
  - `create fija expiresAt = createdAt + 24 h`.
  - `findOne lanza NotFoundException si expiresAt < ahora`.
  - `findOne lanza NotFoundException si hidden = true`.
  - `findOne lanza NotFoundException si visibility='friends' y el lector no está en now_friends del autor`.
  - `toDto no expone email ni phone del autor`.
- [ ] **Step 2: Correr y ver que fallan:** `npx jest src/modules/now/now.service.spec.ts`. Falla con FAIL.
- [ ] **Step 3: Implementar `NowService.create`, `findOne`, `listArea` y `toDto`.**
  - `listArea` filtra por caja con `ST_Intersects(location, ST_MakeEnvelope(...,4326))`, `expires_at > now()`, `hidden = false`, y aplica `canSee`.
  - Las promos salen de un `QueryBuilder` propio sobre `Promotion` unido a `Place` y a `Subscription`: `status = 'active'`, `is_active = true`, local dentro de la caja y `promoVisibleUntil > ahora`.
  - Máximo 200 publicaciones y 100 promos por consulta.
- [ ] **Step 4: Implementar el controller y el módulo**, y registrar el módulo.
- [ ] **Step 5: Correr las pruebas y la compilación:** `npx jest src/modules/now` y `npx tsc --noEmit -p .`. Pasan (PASS) y la compilación no da errores.
- [ ] **Step 6: Commit** con el mensaje `feat(now): publicar, listar por zona y promos de locales con plan`.

### Task 3: Reacciones y reportes

**Files:**
- Modify: `src/modules/now/now.service.ts`, `src/modules/now/now.controller.ts`
- Create: `src/modules/now/dto/react-now.dto.ts`
- Test: `src/modules/now/now-reactions.spec.ts`

**Interfaces:**
- Consumes: `NOW_RADIUS_M`, `computeExpiresAt`, `shouldHideByVotes`, `REPORTS_TO_HIDE` y `REPORTS_PER_DAY` de la Task 1.
- Produces:
  - **`PUT /api/now/posts/:id/reaction`**, con sesión:
    - cuerpo `{ type: 'like' | 'dislike' | 'check', latitude?, longitude? }`;
    - responde `NowPostDto`.
  - **`DELETE /api/now/posts/:id/reaction`**: responde `NowPostDto`.
  - **`POST /api/now/posts/:id/report`**, con sesión:
    - cuerpo `{ reason: string }`;
    - responde `{ ok: true }`;
    - `@Throttle({ default: { ttl: 86_400_000, limit: 20 } })`.

- [ ] **Step 1: Escribir los tests que fallan.**
  - `check sin lat/lng → BadRequestException`.
  - `check a 301 m → ForbiddenException`, calculado con `ST_DWithin`. En la prueba la distancia se simula; la consulta vive en el método `distanceMeters(postId, lat, lng)`.
  - `cambiar de like a dislike deja likes-1, dislikes+1 y recalcula expiresAt`.
  - `la misma reacción dos veces no cambia los contadores`.
  - `al cruzar el margen de 👎 marca hidden=true, hiddenReason='votes'`.
  - `el tercer reporte de usuarios distintos marca hidden=true, hiddenReason='reports'`.
  - `el mismo usuario reportando dos veces cuenta una sola vez`.
- [ ] **Step 2: Correr y ver que fallan:** `npx jest src/modules/now/now-reactions.spec.ts`. Falla con FAIL.
- [ ] **Step 3: Implementar `react`, `unreact` y `report`.** Cada uno va en una transacción y actualiza contadores, `expiresAt` y `hidden`.
- [ ] **Step 4: Correr las pruebas:** `npx jest src/modules/now`. Pasan (PASS).
- [ ] **Step 5: Commit** con el mensaje `feat(now): reacciones 👍👎✅ y reportes`.

### Task 4: Amigos, feed y moderación de admin

**Files:**
- Modify: `src/modules/now/now.service.ts`, `src/modules/now/now.controller.ts`
- Create: `src/modules/now/now-admin.controller.ts`, con `@Controller('admin/now')`, `@UseGuards(JwtAuthGuard, RolesGuard)` y `@Roles('admin')`, como en `admin.controller.ts`
- Test: `src/modules/now/now-friends.spec.ts`

**Interfaces:**
- Produces:
  - **Amigos:**
    - `GET /api/now/friends` responde `{ id, fullName, avatarUrl }[]`;
    - `POST /api/now/friends/:userId` responde 400 si ese usuario no sigue al dueño;
    - `DELETE /api/now/friends/:userId`.
  - **`GET /api/now/feed?scope=following|nearby|friends&lat&lng&page`**, con sesión: responde `{ data: NowPostDto[], total }`.
    - `following`: autores que sigo.
    - `nearby`: hasta 5 km de lat/lng.
    - `friends`: autores que me tienen en su lista, o que yo tengo en la mía.
    - Siempre se respeta `canSee`.
  - **`GET /api/now/mine?page`**, con sesión: responde `{ data: NowPostDto[], total }`, con mis publicaciones (vigentes y vencidas, más nuevas primero) para la fila "Mis publicaciones" del perfil.
  - **Admin:**
    - `GET /api/admin/now/reported` responde una lista de `NowPostDto & { reports, hiddenReason }`, de publicaciones con `hidden = true`;
    - `PATCH /api/admin/now/posts/:id` con `{ hidden: false }` restaura la publicación y borra sus reportes;
    - `DELETE /api/admin/now/posts/:id`.

- [ ] **Step 1: Escribir los tests que fallan.**
  - `agregar amigo que no me sigue → BadRequestException`.
  - `feed friends no incluye una publicación friends de un autor que no me tiene en su lista`.
  - `restaurar pone hidden=false y elimina sus now_reports`.
- [ ] **Step 2: Correr y ver que fallan:** `npx jest src/modules/now/now-friends.spec.ts`. Falla con FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Correr todas las pruebas, la compilación y el lint:** `npx jest src/modules/now`, `npx tsc --noEmit -p .` y `npm run lint`. Todo pasa (PASS).
- [ ] **Step 5: Commit** con el mensaje `feat(now): lista de amigos, feed y moderación de admin`.

## Fase 2 · Panel (`warike_administrativo/apps/dashboard`, rama `feat/ahora-moderacion`)

### Task 5: Publicaciones reportadas en Moderación

**Files:**
- Create: `components/admin/moderacion/NowReportsSection.tsx`
- Modify:
  - `app/(dashboard)/moderacion/page.tsx`, agregando la sección como las demás (`ClaimsSection` y compañía);
  - `lib/api-client.ts`, agregando a `adminApi` las funciones `nowReported()`, `nowRestore(id)` y `nowDelete(id)`.

**Interfaces:**
- Consumes: los endpoints de admin de la Task 4.

- [ ] **Step 1: Implementar la sección.**
  - Lista: miniatura o texto, autor, motivo (`votes` o `reports`), cantidad de reportes y fecha.
  - Botones "Restaurar" y "Borrar", este último con confirmación. Avisos con `toast` de `sonner`.
- [ ] **Step 2: Revisar tipos:** `npx tsc --noEmit -p .`. No da errores en los archivos tocados.
- [ ] **Step 3: Probar en el navegador:** `npx next dev -p 3005` y abrir `/moderacion` con un admin. La sección aparece y, si no hay publicaciones reportadas, dice "No hay publicaciones reportadas".
- [ ] **Step 4: Commit** con el mensaje `feat(moderacion): publicaciones Ahora reportadas`.

## Fase 3 · App (`Mobil_wuariekes`, rama `feat/rediseno-ahora`)

Para todas las tareas de esta fase, la verificación es:
- `flutter analyze` sin errores nuevos;
- `flutter test` en PASS;
- probarlo con `flutter run --dart-define-from-file=dart_defines.json` (más `--dart-define=API_URL=http://<ip-local>:3001/api` si el backend nuevo todavía no está en producción) y compararlo con el boceto correspondiente.

### Task 6: Modelos y llamadas de "Ahora"

**Files:**
- Create: `lib/core/now_models.dart`, `lib/core/now_api.dart`
- Test: `test/now_models_test.dart`

**Interfaces:**
- Consumes: los endpoints de las Tasks 2 a 4.
- Produces:
  - **Modelos:**
    - `class NowPost { id, kind, text, mediaUrl, latitude, longitude, visibility, likes, dislikes, checks, expiresAt, createdAt, authorId, authorName, authorAvatar, myReaction; factory NowPost.fromJson(Map) ; Duration timeLeft(DateTime now) }`;
    - `class NowPromo { id, title, description, imageUrl, visibleUntil, placeId, placeName, latitude, longitude; factory NowPromo.fromJson(Map) }`;
    - `class NowArea { List<NowPost> posts; List<NowPromo> promos }`.
  - **`extension NowApi on ApiClient`**, con estos métodos:
    - `getNowArea({required double minLat, minLng, maxLat, maxLng}) → Future<NowArea>`;
    - `getNowPost(String id)`;
    - `createNowPost({required String kind, String? text, required String visibility, required double latitude, required double longitude, List<int>? bytes, String? filename, String? mimeType}) → Future<NowPost>`. Hace falta un `uploadMultipart` con campos extra en `api_client.dart`: se agrega un parámetro opcional `fields` a `uploadMedia`;
    - `reactNow(String id, String type, {double? lat, double? lng})`;
    - `unreactNow(String id)`;
    - `reportNow(String id, String reason)`;
    - `getNowFeed(String scope, {double? lat, double? lng, int page = 1}) → Future<Paginated<NowPost>>`;
    - `getMyNowPosts({int page = 1}) → Future<Paginated<NowPost>>`;
    - `getFriends()`, `addFriend(String userId)` y `removeFriend(String userId)`.

- [ ] **Step 1: Escribir los tests que fallan.**
  - `NowPost.fromJson lee autor, contadores y expiresAt`.
  - `timeLeft devuelve Duration.zero si ya venció`.
  - `NowPromo.fromJson lee place.latitude/longitude`.
- [ ] **Step 2: Correr y ver que fallan:** `flutter test test/now_models_test.dart`. Falla con FAIL.
- [ ] **Step 3: Implementar los modelos y la extensión.**
- [ ] **Step 4: Correr las pruebas:** `flutter test`. Pasan (PASS).
- [ ] **Step 5: Commit** con el mensaje `feat(now): modelos y API de Ahora en la app`.

### Task 7: Barra nueva y menú del ＋

**Files:**
- Modify: `lib/screens/main_shell.dart`, `lib/screens/profile_screen.dart`
- Create: `lib/widgets/plus_menu.dart`
- Test: `test/main_shell_test.dart`

**Interfaces:**
- Produces:
  - pestañas en orden `ExploreScreen`, `FeedScreen`, `MyLoyaltyScreen`, `ProfileScreen`, con las etiquetas `Explorar`, `Actividad`, `Premios`, `Perfil`;
  - `showPlusMenu(BuildContext)` abre un menú con dos opciones:
    - "Publicar lo que pasa aquí": llama a `showPublishNowSheet` de la Task 9; mientras tanto, a un `TODO` visible que luego se reemplaza;
    - "Sugerir un lugar nuevo": abre `RegisterPlaceScreen`.
  - En el perfil, una fila "Guardados" abre `FavoritesScreen`.

- [ ] **Step 1: Escribir el test que falla.** `la barra muestra Explorar, Actividad, Premios y Perfil, y no Favoritos`, con un `pumpWidget` de `MainShell` y `AuthProvider` simulado (ver `widget_test.dart`).
- [ ] **Step 2: Correr y ver que falla:** `flutter test test/main_shell_test.dart`. Falla con FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4: Correr las pruebas:** `flutter test`. Pasan (PASS).
- [ ] **Step 5: Commit** con el mensaje `feat(app): barra Explorar·Actividad·＋·Premios·Perfil`.

### Task 8: Explorar rediseñado (Locales)

**Files:**
- Modify: `lib/screens/explore_screen.dart`, partiendo sus piezas nuevas en `lib/widgets/`:
  - `explore_bottom_list.dart`;
  - `mode_switch.dart`;
  - `place_list_tile.dart`.

**Interfaces:**
- Produces:
  - `enum ExploreMode { places, now }`;
  - `ModeSwitch(value, onChanged)`;
  - una lista deslizable abajo (`DraggableScrollableSheet`) con el título "Cerca de ti · N", un chip "✨ Sorpréndeme" que abre `DiscoveryScreen`, y tarjetas que muestran foto, ⭐, categoría, distancia, "Desde S/", "Abierto" y "🔥" si `hasActiveBenefit`;
  - el buscador dice "¿Qué se te antoja?" y tiene el avatar a la derecha.

- [ ] **Step 1: Implementar** según el boceto 1 de `app-rediseno.html`. Se mantienen los filtros que ya existen: categoría, abierto y distancia.
- [ ] **Step 2: Verificación de la fase.** Al mover el mapa la lista se actualiza, y al tocar una tarjeta se abre la ficha.
- [ ] **Step 3: Commit** con el mensaje `feat(app): Explorar con lista deslizable y modo Locales/Ahora`.

### Task 9: Capa "Ahora": mapa, franja, publicar y ver

**Files:**
- Create:
  - `lib/screens/now/now_layer.dart` (pines y franja "Hoy cerca de ti");
  - `lib/screens/now/publish_now_sheet.dart`;
  - `lib/screens/now/now_post_screen.dart`.
- Modify: `lib/screens/explore_screen.dart` (cuando `ExploreMode.now`, carga `getNowArea` con la caja visible del mapa) y `lib/widgets/plus_menu.dart` (conectarlo a `showPublishNowSheet`)

**Interfaces:**
- Consumes: la extensión `NowApi` de la Task 6; `geolocator`, que ya está en el proyecto.
- Produces:
  - `showPublishNowSheet(BuildContext)`:
    - pide la posición actual;
    - opciones Foto, Video y Texto con `image_picker`;
    - visibilidad 🌎 Todos (`all`), 👤 Seguidores (`followers`) y 👥 Amigos (`friends`);
    - el aviso "Se publica donde estás (300 m) · dura 24 h";
    - el botón "Publicar como @{nombre}";
    - si responde 429, muestra "Llegaste al límite de 5 publicaciones por hora";
  - `NowPostScreen(postId)`:
    - muestra la media, el autor, "quedan X h", 👍 👎 ✅ con sus conteos y "⚑ Reportar";
    - ✅ aparece apagado con el texto "Acércate para confirmar" si la distancia, calculada en la app con `Geolocator.distanceBetween`, es mayor a 300 m;
  - pines: promo con fondo ají y 🔥; publicación con fondo hierba y 📸, 🎥 o 💬 según `kind`.

- [ ] **Step 1: Escribir el test que falla** en `test/now_models_test.dart`: `canConfirm(distanceMeters) es true hasta 300 y false desde 301`. La función pura `canConfirm` va en `now_models.dart`.
- [ ] **Step 2: Correr y ver que falla:** `flutter test test/now_models_test.dart`. Falla con FAIL.
- [ ] **Step 3: Implementar** según `pantallas-ahora.html`. Un error de red en la capa muestra un `SnackBar` con "No se pudo cargar lo que pasa ahora" y deja el mapa usable.
- [ ] **Step 4: Verificación de la fase.**
  - Se publica un texto y aparece en el mapa.
  - Se da 👍 y sube el contador.
  - Lejos de la publicación, ✅ queda apagado.
- [ ] **Step 5: Commit** con el mensaje `feat(app): capa Ahora con publicar, ver y reaccionar`.

### Task 10: Ficha del local rediseñada

**Files:**
- Modify: `lib/screens/place_detail_screen.dart`, `lib/screens/place_extras.dart`

**Interfaces:**
- Consumes: `getLoyaltyCard`/`getMyLoyaltyCards` (para "Tu tarjeta: X/Y sellos"), `getPlace`, las promociones de `GET /places/:id/promotions` (ver `place_extras.dart`) y la subida de foto y video que ya existe.
- Produces:
  - foto grande con carrusel, botones de volver, guardar y compartir;
  - acciones rápidas: Cómo llegar, WhatsApp, Reservar y Llamar, solo las que tienen dato;
  - caja de la promo del día y tarjeta de premios;
  - pestañas Resumen · Carta · Fotos · Reseñas. Carta solo aparece si `details['claimedByUserId'] != null`;
  - abajo, el botón fijo "📍 Estoy aquí · check-in" y 📷 para subir foto o video sin reseña.

- [ ] **Step 1: Implementar** según el boceto 2.
- [ ] **Step 2: Verificación de la fase.** En un local sin reclamar no aparece la pestaña Carta.
- [ ] **Step 3: Commit** con el mensaje `feat(app): ficha del local rediseñada`.

### Task 11: Check-in rediseñado

**Files:**
- Modify: `lib/screens/new_checkin_screen.dart`
- Test: `test/checkin_comment_test.dart`

**Interfaces:**
- Produces:
  - `String buildCheckinComment(List<String> chips, String text)`: arma `"😋 Rico · 💸 Buen precio — {texto}"`. Sin chips devuelve solo el texto, y sin texto, solo los chips;
  - los chips son: `😋 Rico`, `💸 Buen precio`, `⚡ Rápido`, `🫶 Buena atención`;
  - los puntos que se muestran son `10`, más `5` si hay foto.

- [ ] **Step 1: Escribir los tests que fallan.**

```dart
expect(buildCheckinComment(['😋 Rico'], 'Top'), '😋 Rico — Top');
expect(buildCheckinComment([], 'Top'), 'Top');
expect(buildCheckinComment(['😋 Rico', '⚡ Rápido'], ''), '😋 Rico · ⚡ Rápido');
```

- [ ] **Step 2: Correr y ver que fallan:** `flutter test test/checkin_comment_test.dart`. Falla con FAIL.
- [ ] **Step 3: Implementar** según el boceto 3. "¿Qué pediste?" muestra los platos del local en chips, más la opción "+ Otro".
- [ ] **Step 4: Correr las pruebas:** `flutter test`. Pasan (PASS).
- [ ] **Step 5: Commit** con el mensaje `feat(app): check-in con chips y puntos reales`.

### Task 12: Actividad con check-ins y "Ahora"

**Files:**
- Modify: `lib/screens/feed_screen.dart`
- Test: `test/feed_merge_test.dart`

**Interfaces:**
- Consumes: `getFeed(following: true)`, que ya existe, y `getNowFeed(scope)` de la Task 6.
- Produces:
  - `List<FeedEntry> mergeFeed(List<CheckinItem> checkins, List<NowPost> posts)`: ordena por fecha, de la más nueva a la más vieja;
  - pestañas:
    - Siguiendo: check-ins más publicaciones `following`;
    - Cerca de mí: solo publicaciones `nearby`;
    - Amigos: solo publicaciones `friends`.

- [ ] **Step 1: Escribir el test que falla.** `mergeFeed intercala por fecha descendente`.
- [ ] **Step 2: Correr y ver que falla:** `flutter test test/feed_merge_test.dart`. Falla con FAIL.
- [ ] **Step 3: Implementar** según el boceto 4. Las publicaciones muestran la etiqueta "⚡ quedan X h".
- [ ] **Step 4: Correr las pruebas:** `flutter test`. Pasan (PASS).
- [ ] **Step 5: Commit** con el mensaje `feat(app): Actividad mezcla check-ins y Ahora`.

### Task 13: Premios y Perfil rediseñados, y lista de amigos

**Files:**
- Modify: `lib/screens/my_loyalty_screen.dart`, `lib/screens/profile_screen.dart`
- Create: `lib/screens/friends_screen.dart`

**Interfaces:**
- Consumes: `getMyLoyaltyCards`, `getMyStats`, `getBadges` y los métodos de amigos de la Task 6.
- Produces:
  - **Premios:** una tarjeta por local, con sellos llenos y vacíos, "📍 a X m" si hay posición, y la etiqueta "🎉 ¡Listo para canjear!" cuando se completan los sellos.
  - **Perfil:**
    - avatar, nombre y bio;
    - nivel, racha y check-ins, con barra hacia el siguiente nivel;
    - insignias;
    - filas Mi mapa, Guardados, Mis amigos, Mis publicaciones y Mensajes.
  - **`FriendsScreen`:** muestra mis seguidores con un interruptor "En mis Amigos", que llama a `addFriend` o `removeFriend`.

- [ ] **Step 1: Implementar** según los bocetos 5 y 6.
- [ ] **Step 2: Verificación de la fase.** Al agregar un seguidor a Amigos, aparece en `GET /now/friends`.
- [ ] **Step 3: Commit** con el mensaje `feat(app): Premios, Perfil y lista de Amigos`.

## Cierre

- [ ] **Revisión completa de las ramas.**
  - Backend: `npx jest` y `npm run lint`.
  - App: `flutter analyze` y `flutter test`.
  - Panel: `npx tsc --noEmit`.
- [ ] **Pedir permiso al usuario** para tres cosas:
  1. Aplicar `migrations/add_now_tables.sql` en producción.
  2. Fusionar a `main` las ramas del backend y del panel.
  3. Generar `flutter build appbundle --dart-define-from-file=dart_defines.json` para la prueba cerrada de Play Store.
