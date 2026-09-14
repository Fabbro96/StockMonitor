import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/auth_api.dart';
import '../../core/api/settings_api.dart';
import '../../core/models/settings.dart';
import '../../core/models/user.dart';

// ---------------------------------------------------------------------------
// Helper puri (strategia, mercati, orari): testabili senza widget.
// ---------------------------------------------------------------------------

/// Normalizza il valore `strategy` letto dal server verso i valori UI.
///
/// Il backend non valida il campo e storicamente salva il vocabolario legacy
/// `long_term|short_term|mixed` (bug #1 di exp-1 §5), mentre il select del
/// frontend usa `long|short|mixed`. Un valore sconosciuto ricade su `mixed`.
String normalizeStrategyValue(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'long':
    case 'long_term':
      return 'long';
    case 'short':
    case 'short_term':
      return 'short';
    case 'mixed':
      return 'mixed';
    default:
      return 'mixed';
  }
}

/// Etichetta italiana della strategia (valore UI `long|short|mixed`).
String strategyLabel(String value) {
  switch (value) {
    case 'long':
      return 'Long Term (Cassettista / Valore)';
    case 'short':
      return 'Short Term (Trading / Momentum)';
    default:
      return 'Misto (Equilibrato)';
  }
}

/// Ordine canonico dei mercati inviato al server (stesso del legacy).
const List<String> kMarketOrder = <String>['IT', 'US', 'EU'];

/// Filtra e ordina i mercati selezionati secondo [kMarketOrder].
List<String> orderedMarkets(Iterable<String> selected) {
  final Set<String> set = selected.map((String m) => m.toUpperCase()).toSet();
  return <String>[
    for (final String market in kMarketOrder)
      if (set.contains(market)) market,
  ];
}

/// Orari di default del report: primo invio `09:00`, successivi `18:00`.
List<String> defaultReportTimes() => const <String>['09:00', '18:00'];

/// Valida e normalizza un orario `HH:MM` (accetta anche `H:MM`).
///
/// Restituisce `null` quando l'input non è un orario valido.
String? normalizeTimeValue(String raw) {
  final Match? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final int hours = int.parse(match.group(1)!);
  final int minutes = int.parse(match.group(2)!);
  if (hours > 23 || minutes > 59) return null;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

/// Orario mostrato per l'indice [index] della lista report.
///
/// Se la settings non contiene un valore per quell'indice si applica il
/// default legacy (`09:00` per il primo, `18:00` per gli altri).
String reportTimeAt(List<String> times, int index) {
  if (index >= 0 && index < times.length) {
    final String? normalized = normalizeTimeValue(times[index]);
    if (normalized != null) return normalized;
  }
  return index == 0 ? '09:00' : '18:00';
}

/// Numero editabile senza separatori di migliaia (es. `10000`, `1234.5`).
String formatEditableNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Soglia % di una regola alert: preferisce `threshold_percent` (presente solo
/// nel GET) e ricade su `threshold` (unico campo del POST).
double alertThresholdValue(AlertRule rule) =>
    rule.thresholdPercent ?? rule.threshold;

/// Formatta la soglia % con al massimo due decimali (es. `2`, `2.5`).
String formatThresholdPercent(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

// ---------------------------------------------------------------------------
// Stato impostazioni
// ---------------------------------------------------------------------------

/// Carica (`GET /settings/`) e salva (`PUT /settings/`) le impostazioni utente.
///
/// Il PUT non restituisce `apiStatus`: dopo il salvataggio lo stato mantiene
/// quello letto dal GET, così le card di stato integrazioni non si svuotano.
class SettingsController extends AsyncNotifier<UserSettings> {
  @override
  Future<UserSettings> build() => ref.read(settingsApiProvider).getSettings();

  /// Ricarica le impostazioni (dopo un errore o un refresh manuale).
  Future<void> reload() async {
    if (state.value == null) {
      state = const AsyncLoading<UserSettings>();
    }
    state = await AsyncValue.guard<UserSettings>(
      () => ref.read(settingsApiProvider).getSettings(),
    );
  }

  /// Salva i cinque campi del form. Gli errori vanno al chiamante (toast).
  Future<void> save({
    required String strategy,
    required double budget,
    required List<String> markets,
    required int reportFreq,
    required List<String> reportTimes,
  }) async {
    final UserSettings updated = await ref
        .read(settingsApiProvider)
        .updateSettings(
          strategy: strategy,
          budget: budget,
          markets: markets,
          reportFreq: reportFreq,
          reportTimes: reportTimes,
        );
    final ApiStatus? previousStatus = state.value?.apiStatus;
    state = AsyncData<UserSettings>(
      UserSettings(
        id: updated.id,
        strategy: updated.strategy,
        markets: updated.markets,
        budget: updated.budget,
        totalBudget: updated.totalBudget,
        reportFreq: updated.reportFreq,
        reportTimes: updated.reportTimes,
        apiStatus: previousStatus ?? updated.apiStatus,
      ),
    );
  }
}

/// Impostazioni utente correnti.
final AsyncNotifierProvider<SettingsController, UserSettings> settingsProvider =
    AsyncNotifierProvider<SettingsController, UserSettings>(
      SettingsController.new,
    );

// ---------------------------------------------------------------------------
// Regole alert
// ---------------------------------------------------------------------------

/// Lista delle regole alert (`GET/POST/DELETE /settings/alerts`).
class AlertRulesController extends AsyncNotifier<List<AlertRule>> {
  @override
  Future<List<AlertRule>> build() =>
      ref.read(settingsApiProvider).getAlertRules();

  /// Ricarica la lista (mantiene i dati correnti durante il refresh).
  Future<void> reload() async {
    if (state.value == null) {
      state = const AsyncLoading<List<AlertRule>>();
    }
    state = await AsyncValue.guard<List<AlertRule>>(
      () => ref.read(settingsApiProvider).getAlertRules(),
    );
  }

  /// Aggiunge una regola.
  ///
  /// Il POST non restituisce `name`/`threshold_percent`: la risposta viene
  /// inserita in coda se ha un `id` valido, altrimenti si ricarica dal server
  /// (parità con il legacy, niente id inventati non cancellabili).
  Future<AlertRule> add({
    required String ticker,
    required double threshold,
    required String direction,
  }) async {
    final AlertRule created = await ref
        .read(settingsApiProvider)
        .addAlertRule(
          ticker: ticker,
          threshold: threshold,
          direction: direction,
        );
    if (created.id > 0) {
      final List<AlertRule> current = state.value ?? const <AlertRule>[];
      state = AsyncData<List<AlertRule>>(<AlertRule>[...current, created]);
    } else {
      await reload();
    }
    return created;
  }

  /// Elimina una regola e la rimuove dallo stato locale.
  Future<void> remove(int id) async {
    await ref.read(settingsApiProvider).deleteAlertRule(id);
    final List<AlertRule>? current = state.value;
    if (current == null || !ref.mounted) return;
    state = AsyncData<List<AlertRule>>(<AlertRule>[
      for (final AlertRule rule in current)
        if (rule.id != id) rule,
    ]);
  }
}

/// Regole alert configurate.
final AsyncNotifierProvider<AlertRulesController, List<AlertRule>>
alertRulesProvider =
    AsyncNotifierProvider<AlertRulesController, List<AlertRule>>(
      AlertRulesController.new,
    );

// ---------------------------------------------------------------------------
// Gestione utenti (admin)
// ---------------------------------------------------------------------------

/// Lista utenti (`GET /auth/users`, solo admin) con mutazioni.
class UsersController extends AsyncNotifier<List<AuthUser>> {
  @override
  Future<List<AuthUser>> build() => ref.read(authApiProvider).users();

  /// Ricarica l'elenco utenti.
  Future<void> reload() async {
    if (state.value == null) {
      state = const AsyncLoading<List<AuthUser>>();
    }
    state = await AsyncValue.guard<List<AuthUser>>(
      () => ref.read(authApiProvider).users(),
    );
  }

  /// Crea un utente e ricarica l'elenco.
  Future<void> create({
    required String username,
    required String password,
    required bool isAdmin,
  }) async {
    await ref
        .read(authApiProvider)
        .createUser(username: username, password: password, isAdmin: isAdmin);
    await reload();
  }

  /// Elimina un utente e ricarica l'elenco.
  Future<void> remove(int userId) async {
    await ref.read(authApiProvider).deleteUser(userId);
    await reload();
  }

  /// Reimposta la password di un utente (endpoint admin).
  Future<void> resetPassword(int userId, String newPassword) async {
    await ref
        .read(authApiProvider)
        .resetUserPassword(userId: userId, newPassword: newPassword);
  }
}

/// Utenti registrati (caricato solo quando l'utente corrente è admin).
final AsyncNotifierProvider<UsersController, List<AuthUser>> usersProvider =
    AsyncNotifierProvider<UsersController, List<AuthUser>>(UsersController.new);
