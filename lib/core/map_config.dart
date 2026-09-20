import 'package:flutter_map/flutter_map.dart';

/// Llave pública de Mapbox. No va en el código: se pasa al compilar con
/// `flutter run --dart-define-from-file=dart_defines.json` (archivo local, fuera de git).
const String mapboxAccessToken = String.fromEnvironment('MAPBOX_TOKEN');

/// Shared Mapbox tile layer — used by every map in the app.
TileLayer buildMapboxTileLayer() {
  return TileLayer(
    // "light-v11": minimal basemap with no default restaurant/shop POI
    // icons, so only Wuarikes' own markers show on the map. Swap back to
    // "streets-v12" (or a custom Mapbox Studio style) if more map detail
    // (street/place labels) is wanted instead.
    urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/light-v11/tiles/512/{z}/{x}/{y}@2x?access_token={accessToken}',
    additionalOptions: const {'accessToken': mapboxAccessToken},
    tileDimension: 512,
    zoomOffset: -1,
    userAgentPackageName: 'com.wuarikes.wuarikes_app',
  );
}
