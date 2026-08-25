/// Analytics is web-only. On Android, iOS and in tests this does nothing, so
/// no tracking code ships in the APK.
void track(String name, Map<String, Object?> props) {}
