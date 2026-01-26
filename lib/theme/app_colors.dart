import 'package:flutter/material.dart';

/// Centrale kleur constanten voor Boerenbridge/Lekkerkaarten
/// Warme, huiselijke kleuren passend bij het kaartspel thema
class AppColors {
  AppColors._();

  // Primaire warme kleuren
  static const Color warmBeige = Color(0xFFF5EBD7);       // Card achtergrond (UI cards)
  static const Color warmOffWhite = Color(0xFFFFFBF5);   // Scaffold achtergrond
  static const Color warmBrown = Color(0xFF8B7355);      // Accenten, borders
  static const Color warmBrownLight = Color(0xFFB8A088); // Subtiele borders
  static const Color warmCream = Color(0xFFFAF6ED);      // Lichte variant

  // Accent kleuren
  static const Color forestGreen = Color(0xFF1B5E20);    // Primary (kaartspel groen)
  static const Color goldAccent = Color(0xFFD4AF37);     // Winnaar/speciaal

  // Status kleuren
  static const Color statusGreen = Color(0xFF00AA00);    // Goed/correct
  static const Color statusRed = Color(0xFFCC0000);      // Fout
  static const Color statusOrange = Color(0xFFFF8C00);   // Overbod
  static const Color statusBlue = Color(0xFF1976D2);     // Onderbod

  // Speelkaarten (blijven wit, niet beige!)
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color cardBorderLight = Color(0xFFE0E0E0);
  static const Color cardBorderWarm = Color(0xFFB8A088);
  static const Color cardSuitRed = Color(0xFFD32F2F);
  static const Color cardSuitBlack = Color(0xFF212121);
}
