import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Bridges to the `penFightTrack` helper defined in web/index.html, which
/// forwards to Vercel Web Analytics.
@JS('penFightTrack')
external void _penFightTrack(JSString name, JSObject props);

@JS('penFightTrack')
external JSAny? get _handle;

void track(String name, Map<String, Object?> props) {
  // The helper is absent when the page is served outside Vercel.
  if (_handle == null) return;

  final payload = JSObject();
  for (final entry in props.entries) {
    final v = entry.value;
    payload.setProperty(
      entry.key.toJS,
      switch (v) {
        final String s => s.toJS,
        final num n => n.toJS,
        final bool b => b.toJS,
        _ => v.toString().toJS,
      },
    );
  }
  _penFightTrack(name.toJS, payload);
}
