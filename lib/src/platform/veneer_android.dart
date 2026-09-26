/// Android registration. Veneer has no Android native code: its widgets
/// render Flutter replicas there, so registering does nothing. Declaring the
/// platform lets apps (and pub.dev) see Android as supported.
class VeneerAndroid {
  /// Called by Flutter's generated plugin registrant.
  static void registerWith() {}
}
