import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A fantasy journal palette inspired by the game's mission menus.
abstract final class AppDesign {
  static const background = Color(0xFF11171D);
  static const panel = Color(0xFF1E272E);
  static const gold = Color(0xFFE2C58D);
  static const muted = Color(0xFFABB4B8);
  static const border = Color(0xFF4D493D);
  static const mint = Color(0xFFA5CCB8);
  static const crystal = Color(0xFFAAD8EA);

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
      primary: gold,
      onPrimary: background,
      secondary: mint,
      surface: panel,
      onSurface: const Color(0xFFF2EDE2),
      onSurfaceVariant: muted,
      outline: border,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: gold,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: muted,
          height: 1.5,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: gold,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 80,
        centerTitle: false,
        titleSpacing: 0,
      ),
      cardTheme: const CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 5),
        shape: BeveledRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFF151F26),
        side: const BorderSide(color: Color(0xFF34434B)),
        labelStyle: const TextStyle(color: Color(0xFFC6D4D8), fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: const BorderSide(color: Color(0xFF788477), width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? mint : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(background),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(140, 46)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: border)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? gold : panel,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? background : muted,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: mint,
        linearTrackColor: Color(0xFF303D40),
        linearMinHeight: 5,
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        titleTextStyle: const TextStyle(
          color: gold,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF151F26),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: gold),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: BeveledRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
    );
  }
}

class JournalEmblem extends StatelessWidget {
  const JournalEmblem({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF2C302C),
          border: Border.all(color: AppDesign.gold),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Transform.rotate(
          angle: -math.pi / 4,
          child: const Icon(
            Icons.auto_awesome,
            color: AppDesign.gold,
            size: 23,
          ),
        ),
      ),
    ),
  );
}
