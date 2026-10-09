import 'google_maps_bootstrap_stub.dart'
    if (dart.library.html) 'google_maps_bootstrap_web.dart' as impl;

/// Load the maps JavaScript API before constructing GoogleMap on Flutter Web.
/// Native map SDKs are managed by their platform plugins.
Future<bool> ensureGoogleMapsReady(String apiKey) =>
    impl.ensureGoogleMapsReady(apiKey);
