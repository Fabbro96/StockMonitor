import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage.dart';

/// Controller del tema: legge/scrive la preferenza su [AppStorage] e espone il
/// [ThemeMode] a MaterialApp.
///
/// Default: [ThemeMode.system] (come `getTheme()` del frontend: preferenza
/// salvata, altrimenti `prefers-color-scheme`). Il toggle scrive sempre
/// `light`/`dark` in storage, come il vecchio `app_theme`.
class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Carica la preferenza persistita. Da chiamare una volta all'avvio.
  Future<void> load() async {
    final String? stored = await ref.read(appStorageProvider).getThemeMode();
    state = _fromStorage(stored);
  }

  /// Alterna chiaro/scuro e persiste la scelta.
  ///
  /// Se lo stato corrente è [ThemeMode.system], il toggle parte dalla
  /// luminosità effettiva di sistema per andare sul tema opposto.
  Future<void> toggle() async {
    final ThemeMode next = _isDark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    await ref
        .read(appStorageProvider)
        .setThemeMode(next == ThemeMode.dark ? 'dark' : 'light');
  }

  bool get _isDark => switch (state) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system =>
          PlatformDispatcher.instance.platformBrightness == Brightness.dark,
      };

  static ThemeMode _fromStorage(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// [ThemeMode] corrente dell'app (light/dark/system).
final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
