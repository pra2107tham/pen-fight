import 'package:flutter/material.dart';

/// Tokens lifted verbatim from the design's DESIGN TOKENS card.
class PF {
  // Ink
  static const blue = Color(0xFF1E3FD8);
  static const red = Color(0xFFD62828);
  static const black = Color(0xFF14161A);
  static const green = Color(0xFF0E8A4F);
  static const orange = Color(0xFFF26419);
  static const purple = Color(0xFF7B3FE4);

  // Surfaces
  static const paper = Color(0xFFFBF7EC);
  static const rule = Color(0xFFCFE0EE);
  static const margin = Color(0xFFE9A19A);
  static const canvas = Color(0xFFE6E1D6);
  static const meterTrack = Color(0xFFE7E1D2);

  static const inks = [blue, red, black, green, orange];

  /// Shape tags so colour is never the only way to tell pens apart.
  static const badges = ['●', '▲', '■', '◆', '★'];

  /// Default names, matching the design's roster.
  static const seatNames = ['YOU', 'RIYA', 'ARJUN', 'MEHA', 'DEV'];

  static Color inkFor(int seat) => inks[seat % inks.length];
  static String badgeFor(int seat) => badges[seat % badges.length];

  // Type
  static const display = 'PermanentMarker';
  static const sans = 'Archivo';
  static const mono = 'IBMPlexMono';

  static TextStyle marker(double size, {Color color = black, double h = 1}) =>
      TextStyle(
          fontFamily: display, fontSize: size, color: color, height: h);

  static TextStyle bold(double size,
          {Color color = black, double w = 800, double ls = 0, double h = 1.1}) =>
      TextStyle(
        fontFamily: sans,
        fontSize: size,
        color: color,
        height: h,
        fontWeight: FontWeight.values[(w ~/ 100) - 1],
        letterSpacing: ls,
      );

  static TextStyle code(double size, {Color color = black, double ls = 0}) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size,
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: ls,
      );
}

/// The design's signature "solid offset shadow" — never blurred.
List<BoxShadow> offsetShadow(double d, [Color c = PF.black]) =>
    [BoxShadow(color: c, offset: Offset(d, d), blurRadius: 0)];
