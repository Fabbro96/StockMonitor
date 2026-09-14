import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/auth_api.dart';
import '../../core/api/settings_api.dart';
import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models/settings.dart';
import '../../core/models/user.dart';
import '../../core/session/auth_controller.dart';
import '../../core/storage.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/badges.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_content.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stepper_input.dart';
import '../../widgets/toast.dart';
import 'settings_dialogs.dart';
import 'settings_providers.dart';

/// Impostazioni con parità funzionale con `settings.html` / `settings.js`:
/// budget, strategia e mercati, notifiche report, regole alert (con BOTH),
/// cambio password, gestione utenti admin (con reset password), stato
/// integrazioni e sezione Server (carryover Gate A F8).
///
/// La sezione Server permette di cambiare l'indirizzo del backend su Android
/// (su web il client usa la stessa origine e i campi sono disabilitati): il
/// salvataggio azzera la sessione e riporta al login.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Crea la schermata Impostazioni.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // --- Budget ------------------------------------------------------------
  final TextEditingController _budgetController = TextEditingController();

  // --- Strategia e mercati ----------------------------------------------
  String _strategy = 'mixed';
  final Set<String> _markets = <String>{'IT', 'US', 'EU'};

  // --- Notifiche & report ------------------------------------------------
  int _reportFreq = 2;
  final List<TextEditingController> _timeControllers = <TextEditingController>[
    for (final String time in defaultReportTimes())
      TextEditingController(text: time),
  ];

  // --- Regole alert ------------------------------------------------------
  final TextEditingController _alertTickerController = TextEditingController();
  final TextEditingController _thresholdController = TextEditingController();
  String _alertDirection = 'UP';

  // --- Sicurezza ---------------------------------------------------------
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  String? _passwordError;

  // --- Gestione utenti (admin) ------------------------------------------
  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newUserPasswordController =
      TextEditingController();
  bool _newUserIsAdmin = false;

  // --- Server ------------------------------------------------------------
  final TextEditingController _serverController = TextEditingController();
  String _currentServer = '';
  bool _serverLoaded = false;

  // --- Stati di caricamento dei pulsanti ---------------------------------
  bool _savingSettings = false;
  bool _testingTelegram = false;
  bool _addingAlert = false;
  bool _changingPassword = false;
  bool _creatingUser = false;
  bool _serverSaving = false;

  /// Ultime impostazioni applicate al form (evita ri-applicazioni a ogni build).
  UserSettings? _appliedSettings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      unawaited(_loadServerInfo());
    });
  }

  @override
  void dispose() {
    _budgetController.dispose();
    _alertTickerController.dispose();
    _thresholdController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _newUsernameController.dispose();
    _newUserPasswordController.dispose();
    _serverController.dispose();
    for (final TextEditingController controller in _timeControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Idratazione dei campi
  // -------------------------------------------------------------------------

  /// Copia le impostazioni caricate nei controller/select del form.
  void _applySettings(UserSettings settings) {
    _appliedSettings = settings;
    _budgetController.text = formatEditableNumber(
      settings.budget > 0 ? settings.budget : 10000.0,
    );
    _strategy = normalizeStrategyValue(settings.strategy);
    _markets
      ..clear()
      ..addAll(settings.markets.map((String m) => m.toUpperCase()));
    _reportFreq = settings.reportFreq.clamp(1, 4);
    _syncTimeControllers(freq: _reportFreq, values: settings.reportTimes);
  }

  /// Allinea il numero di campi orario alla frequenza scelta.
  ///
  /// Con [values] i testi vengono riletti dal server; senza [values] i valori
  /// già digitati restano e i campi nuovi ricevono i default legacy.
  void _syncTimeControllers({required int freq, List<String>? values}) {
    while (_timeControllers.length < freq) {
      _timeControllers.add(TextEditingController());
    }
    while (_timeControllers.length > freq) {
      _timeControllers.removeLast().dispose();
    }
    for (var i = 0; i < freq; i++) {
      final TextEditingController controller = _timeControllers[i];
      if (values != null) {
        controller.text = reportTimeAt(values, i);
      } else if (normalizeTimeValue(controller.text) == null) {
        controller.text = reportTimeAt(const <String>[], i);
      }
    }
  }

  /// Carica l'URL server corrente (origine web oppure storage/env su native).
  Future<void> _loadServerInfo() async {
    String current;
    if (kIsWeb) {
      final Uri base = Uri.base;
      current = '${base.scheme}://${base.authority}';
    } else {
      final String? stored = await ref
          .read(appStorageProvider)
          .getServerBaseUrl();
      final String env = AppConfig.apiBaseUrlFromEnv.trim();
      if (stored != null && stored.isNotEmpty) {
        current = AppConfig.normalizeOrigin(stored);
      } else if (env.isNotEmpty) {
        current = AppConfig.normalizeOrigin(env);
      } else {
        current = '';
      }
    }
    if (!mounted) return;
    setState(() {
      _currentServer = current;
      _serverLoaded = true;
      _serverController.text = current;
    });
  }

  // -------------------------------------------------------------------------
  // Azioni
  // -------------------------------------------------------------------------

  Future<void> _saveSettings() async {
    final double? budget = _parseDecimal(_budgetController.text);
    if (budget == null || budget < 100) {
      showAppToast(
        context,
        message: 'Inserisci un budget valido (minimo 100 €)',
        type: AppToastType.error,
      );
      return;
    }

    final List<String> times = <String>[];
    for (var i = 0; i < _reportFreq; i++) {
      final String? normalized = normalizeTimeValue(_timeControllers[i].text);
      if (normalized == null) {
        showAppToast(
          context,
          message: 'Inserisci orari validi nel formato HH:MM',
          type: AppToastType.error,
        );
        return;
      }
      times.add(normalized);
    }

    setState(() => _savingSettings = true);
    try {
      await ref
          .read(settingsProvider.notifier)
          .save(
            strategy: _strategy,
            budget: budget,
            markets: orderedMarkets(_markets),
            reportFreq: _reportFreq,
            reportTimes: times,
          );
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Impostazioni salvate con successo!',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante il salvataggio delle impostazioni',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _testTelegram() async {
    final ApiStatus? status = ref.read(settingsProvider).value?.apiStatus;
    if (status == null || !status.telegram) {
      showAppToast(
        context,
        message: 'Telegram non configurato: verifica token e chat_id in .env',
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _testingTelegram = true);
    try {
      await ref.read(settingsApiProvider).testTelegram();
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Messaggio di test Telegram inviato!',
        type: AppToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore invio messaggio: verifica token e chat_id in .env',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _testingTelegram = false);
    }
  }

  Future<void> _addAlertRule() async {
    final String ticker = _alertTickerController.text.trim().toUpperCase();
    final double? threshold = _parseDecimal(_thresholdController.text);
    if (ticker.isEmpty || threshold == null) {
      showAppToast(
        context,
        message: 'Compila tutti i campi della regola alert',
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _addingAlert = true);
    try {
      await ref
          .read(alertRulesProvider.notifier)
          .add(
            ticker: ticker,
            threshold: threshold,
            direction: _alertDirection,
          );
      if (!mounted) return;
      _alertTickerController.clear();
      _thresholdController.clear();
      showAppToast(
        context,
        message: 'Regola per $ticker aggiunta',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante il salvataggio dell\'alert',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _addingAlert = false);
    }
  }

  Future<void> _deleteAlertRule(AlertRule rule) async {
    final bool confirmed = await showSettingsConfirmDialog(
      context,
      title: 'Elimina regola alert',
      message: 'Sei sicuro di voler eliminare questa regola di alert?',
      confirmLabel: 'Elimina',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(alertRulesProvider.notifier).remove(rule.id);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Regola eliminata con successo',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante l\'eliminazione della regola',
        type: AppToastType.error,
      );
    }
  }

  Future<void> _changePassword() async {
    final String currentPassword = _currentPasswordController.text;
    final String newPassword = _newPasswordController.text;

    setState(() => _passwordError = null);
    if (currentPassword.isEmpty || newPassword.isEmpty) {
      showAppToast(
        context,
        message: 'Inserisci sia la password attuale che la nuova',
        type: AppToastType.error,
      );
      return;
    }
    if (newPassword.length < 8) {
      showAppToast(
        context,
        message: 'La nuova password deve contenere almeno 8 caratteri',
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _changingPassword = true);
    try {
      await ref
          .read(authApiProvider)
          .changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          );
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      showAppToast(
        context,
        message: 'Password aggiornata con successo!',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _passwordError = error.message);
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      const String message = 'Errore durante la modifica della password';
      setState(() => _passwordError = message);
      showAppToast(context, message: message, type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _createUser() async {
    final String username = _newUsernameController.text.trim();
    final String password = _newUserPasswordController.text;

    if (username.isEmpty || password.isEmpty) {
      showAppToast(
        context,
        message: 'Compila nome utente e password',
        type: AppToastType.error,
      );
      return;
    }
    if (password.length < 8) {
      showAppToast(
        context,
        message: 'La password deve contenere almeno 8 caratteri',
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _creatingUser = true);
    try {
      await ref
          .read(usersProvider.notifier)
          .create(
            username: username,
            password: password,
            isAdmin: _newUserIsAdmin,
          );
      if (!mounted) return;
      _newUsernameController.clear();
      _newUserPasswordController.clear();
      setState(() => _newUserIsAdmin = false);
      showAppToast(
        context,
        message: 'Utente "$username" creato con successo!',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante la creazione dell\'utente',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _creatingUser = false);
    }
  }

  Future<void> _deleteUser(AuthUser user) async {
    final bool confirmed = await showSettingsConfirmDialog(
      context,
      title: 'Elimina utente',
      message: 'Sei sicuro di voler eliminare l\'utente "${user.username}"?',
      confirmLabel: 'Elimina',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(usersProvider.notifier).remove(user.id);
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Utente "${user.username}" eliminato con successo',
        type: AppToastType.success,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppToast(context, message: error.message, type: AppToastType.error);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante l\'eliminazione dell\'utente',
        type: AppToastType.error,
      );
    }
  }

  Future<void> _saveServer() async {
    final String raw = _serverController.text.trim();
    if (!AppConfig.isValidOrigin(raw)) {
      setState(() {});
      return;
    }
    final String normalized = AppConfig.normalizeOrigin(raw);
    if (normalized == _currentServer) return;

    final bool confirmed = await showSettingsConfirmDialog(
      context,
      title: 'Modifica indirizzo server',
      message:
          'Cambiando server la sessione corrente verrà chiusa e dovrai '
          'effettuare di nuovo il login. Continuare?',
      confirmLabel: 'Conferma',
    );
    if (!confirmed || !mounted) return;

    setState(() => _serverSaving = true);
    try {
      // Il cambio server bumpa l'epoch: lo scope (e questa schermata) viene
      // smontato e la guardia del router porta da sola a `/login`. Il feedback
      // è la `sessionNotice` consumata dalla LoginScreen: un toast qui non
      // sarebbe visibile.
      await ref.read(authControllerProvider.notifier).changeServer(normalized);
    } catch (_) {
      if (!mounted) return;
      showAppToast(
        context,
        message: 'Errore durante il salvataggio dell\'indirizzo server',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _serverSaving = false);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AuthUser? me = ref.watch(authControllerProvider).value?.user;
    final bool isAdmin = me?.isAdmin ?? false;
    final AsyncValue<UserSettings> settingsAsync = ref.watch(settingsProvider);
    final AsyncValue<List<AlertRule>> alertsAsync = ref.watch(
      alertRulesProvider,
    );
    final AsyncValue<List<AuthUser>>? usersAsync = isAdmin
        ? ref.watch(usersProvider)
        : null;

    _listenErrors<UserSettings>(
      settingsProvider,
      'Errore nel caricamento delle impostazioni',
    );
    _listenErrors<List<AlertRule>>(
      alertRulesProvider,
      'Errore nel caricamento delle regole alert',
    );
    if (isAdmin) {
      _listenErrors<List<AuthUser>>(
        usersProvider,
        'Errore nel caricamento degli utenti',
      );
    }

    // Applica le impostazioni ai controller una sola volta per caricamento,
    // anche quando arrivano dopo un retry della pagina.
    final UserSettings? loaded = settingsAsync.value;
    if (loaded != null && !identical(loaded, _appliedSettings)) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) return;
        final UserSettings? latest = ref.read(settingsProvider).value;
        if (latest == null || identical(latest, _appliedSettings)) return;
        setState(() => _applySettings(latest));
      });
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: loaded == null
              ? _buildLoadState(settingsAsync)
              : PageContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _budgetSection(),
                      const SizedBox(height: AppSpacing.s16),
                      _strategySection(),
                      const SizedBox(height: AppSpacing.s16),
                      _notificationsSection(),
                      const SizedBox(height: AppSpacing.s16),
                      _alertRulesSection(alertsAsync),
                      const SizedBox(height: AppSpacing.s16),
                      _securitySection(),
                      if (isAdmin) ...<Widget>[
                        const SizedBox(height: AppSpacing.s16),
                        _adminUsersSection(usersAsync!),
                      ],
                      const SizedBox(height: AppSpacing.s16),
                      _integrationsSection(loaded),
                      const SizedBox(height: AppSpacing.s16),
                      _serverSection(),
                    ],
                  ),
                ),
        ),
        _buildSaveBar(loaded != null),
      ],
    );
  }

  /// Ascolta un provider e mostra il messaggio dell'errore una sola volta.
  void _listenErrors<T>(
    AsyncNotifierProvider<AsyncNotifier<T>, T> provider,
    String fallbackMessage,
  ) {
    ref.listen<AsyncValue<T>>(provider, (
      AsyncValue<T>? previous,
      AsyncValue<T> next,
    ) {
      final Object? error = next.error;
      if (error == null || identical(previous?.error, error)) return;
      if (!mounted) return;
      showAppToast(
        context,
        message: error is ApiException ? error.message : fallbackMessage,
        type: AppToastType.error,
      );
    });
  }

  Widget _buildLoadState(AsyncValue<UserSettings> settingsAsync) {
    if (settingsAsync.hasError) {
      return PageContent(
        child: AppCard(
          child: EmptyState(
            icon: const Icon(Icons.error_outline),
            message: 'Errore nel caricamento delle impostazioni.',
            actions: <Widget>[
              AppButton(
                label: '↻ Riprova',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () => ref.read(settingsProvider.notifier).reload(),
              ),
            ],
          ),
        ),
      );
    }
    return const PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SkeletonCard(height: 120),
          SizedBox(height: AppSpacing.s16),
          SkeletonCard(height: 110),
          SizedBox(height: AppSpacing.s16),
          SkeletonCard(height: 140),
        ],
      ),
    );
  }

  Widget _buildSaveBar(bool enabled) {
    final AppTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: t.shadowMd,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            AppButton(
              label: 'Salva Impostazioni',
              loading: _savingSettings,
              loadingLabel: 'Salvataggio...',
              onPressed: enabled ? _saveSettings : null,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 1. Budget
  // -------------------------------------------------------------------------

  Widget _budgetSection() {
    final AppTokens t = context.tokens;
    final Widget budgetField = _LabeledControl(
      label: 'Capitale da Investire (€)',
      child: StepperInput(
        controller: _budgetController,
        min: 100,
        step: 1000,
        hint: 'Es. 10000',
        large: true,
        expand: true,
        semanticsLabel: 'Quanti soldi vuoi investire',
        decreaseLabel: 'Diminuisci budget (−1.000€)',
        increaseLabel: 'Aumenta budget (+1.000€)',
      ),
    );

    final Widget presets = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Scorciatoie veloci:',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 11.8,
            height: 1.4,
            fontFamilyFallback: AppTokens.fontFallback,
          ),
        ),
        const SizedBox(height: AppSpacing.s6),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: <Widget>[
            for (final (String label, double value) in _budgetPresets)
              AppButton(
                label: label,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.xs,
                onPressed: () => _setBudget(value),
              ),
          ],
        ),
      ],
    );

    return AppCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: '💶 Quanti soldi vuoi investire? (Capitale / Budget Totale)',
            subtitle:
                'Indica la somma complessiva (in Euro) che intendi investire '
                'o allocare. Questo valore permette al Rebalancer Intelligente '
                'di calcolare le percentuali target e la liquidità residua, e '
                'all\'IA di Gemini di modulare le quote suggerite.',
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    budgetField,
                    const SizedBox(height: AppSpacing.s14),
                    presets,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  SizedBox(width: 300, child: budgetField),
                  const SizedBox(width: AppSpacing.s22),
                  Expanded(child: presets),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _setBudget(double value) {
    _budgetController.text = formatEditableNumber(value);
    _budgetController.selection = TextSelection.collapsed(
      offset: _budgetController.text.length,
    );
    setState(() {});
  }

  // -------------------------------------------------------------------------
  // 2. Strategia & mercati
  // -------------------------------------------------------------------------

  Widget _strategySection() {
    final Widget strategyField = _LabeledControl(
      label: 'Orizzonte Temporale',
      child: DropdownButtonFormField<String>(
        initialValue: _strategy,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final String value in const <String>['long', 'short', 'mixed'])
            DropdownMenuItem<String>(
              value: value,
              child: Text(strategyLabel(value)),
            ),
        ],
        onChanged: (String? value) {
          if (value != null) setState(() => _strategy = value);
        },
      ),
    );

    final Widget marketsField = _LabeledControl(
      label: 'Mercati di Interesse',
      child: Wrap(
        spacing: AppSpacing.s16,
        runSpacing: AppSpacing.s8,
        children: <Widget>[
          _MarketCheckbox(
            label: 'Italia (MIB)',
            value: _markets.contains('IT'),
            onChanged: (bool value) => _toggleMarket('IT', value),
          ),
          _MarketCheckbox(
            label: 'USA (S&P500/Nasdaq)',
            value: _markets.contains('US'),
            onChanged: (bool value) => _toggleMarket('US', value),
          ),
          _MarketCheckbox(
            label: 'Europa',
            value: _markets.contains('EU'),
            onChanged: (bool value) => _toggleMarket('EU', value),
          ),
        ],
      ),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: '🎯 Strategia di Investimento & Rischio',
            subtitle: 'Personalizza il comportamento dell\'IA nell\'elaborazione dei consigli',
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    strategyField,
                    const SizedBox(height: AppSpacing.s14),
                    marketsField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: strategyField),
                  const SizedBox(width: AppSpacing.s14),
                  Expanded(child: marketsField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _toggleMarket(String market, bool value) {
    setState(() {
      if (value) {
        _markets.add(market);
      } else {
        _markets.remove(market);
      }
    });
  }

  // -------------------------------------------------------------------------
  // 3. Notifiche & report
  // -------------------------------------------------------------------------

  Widget _notificationsSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: '🔔 Notifiche & Invio Report',
            subtitle: 'Configura gli orari di ricezione dei riassunti giornalieri su Telegram',
          ),
          _LabeledControl(
            label: 'Frequenza Giornaliera Report',
            child: SizedBox(
              width: 210,
              child: DropdownButtonFormField<int>(
                initialValue: _reportFreq,
                isExpanded: true,
                items: <DropdownMenuItem<int>>[
                  for (var i = 1; i <= 4; i++)
                    DropdownMenuItem<int>(
                      value: i,
                      child: Text(
                        i == 1 ? '1 volta al giorno' : '$i volte al giorno',
                      ),
                    ),
                ],
                onChanged: (int? value) {
                  if (value == null) return;
                  setState(() {
                    _reportFreq = value;
                    _syncTimeControllers(freq: value);
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          Text('Orari di Invio (HH:MM)', style: AppText.formLabel(context)),
          const SizedBox(height: AppSpacing.s6),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: <Widget>[
              for (var i = 0; i < _reportFreq; i++)
                _TimeField(
                  label: i == 0
                      ? 'Orario di invio report (primo invio)'
                      : 'Orario di invio report ${i + 1}',
                  controller: _timeControllers[i],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Container(
            padding: const EdgeInsets.only(top: AppSpacing.s16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.tokens.border)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Invia Messaggio Test Telegram',
                variant: AppButtonVariant.ghost,
                loading: _testingTelegram,
                onPressed: _testTelegram,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 4. Regole alert
  // -------------------------------------------------------------------------

  Widget _alertRulesSection(AsyncValue<List<AlertRule>> alertsAsync) {
    final List<AlertRule> rules = alertsAsync.value ?? const <AlertRule>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: '⚡ Regole Alert Istantanee (Take Profit / Stop Loss)',
            subtitle: 'Ricevi una notifica immediata quando un titolo supera una certa soglia di variazione',
          ),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _alertTickerController,
                  textCapitalization: TextCapitalization.characters,
                  style: AppText.small(context),
                  decoration: const InputDecoration(hintText: 'Ticker'),
                  onSubmitted: (String value) =>
                      _alertTickerController.text = value.toUpperCase(),
                ),
              ),
              SizedBox(
                width: 170,
                child: StepperInput(
                  controller: _thresholdController,
                  step: 0.5,
                  decimals: 2,
                  hint: 'Var. %',
                  expand: true,
                  semanticsLabel: 'Soglia percentuale variazione',
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: _alertDirection,
                  isExpanded: true,
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'UP',
                      child: Text('Al Rialzo (UP)'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'DOWN',
                      child: Text('Al Ribasso (DOWN)'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'BOTH',
                      child: Text('Entrambe (BOTH)'),
                    ),
                  ],
                  onChanged: (String? value) {
                    if (value != null) setState(() => _alertDirection = value);
                  },
                ),
              ),
              AppButton(
                label: 'Aggiungi',
                loading: _addingAlert,
                onPressed: _addAlertRule,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          _buildAlertRulesContent(alertsAsync, rules),
        ],
      ),
    );
  }

  Widget _buildAlertRulesContent(
    AsyncValue<List<AlertRule>> alertsAsync,
    List<AlertRule> rules,
  ) {
    if (rules.isEmpty) {
      if (alertsAsync.isLoading) {
        return const Column(
          children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
        );
      }
      if (alertsAsync.hasError) {
        return EmptyState(
          icon: const Icon(Icons.error_outline),
          message: 'Errore nel caricamento delle regole alert.',
          actions: <Widget>[
            AppButton(
              label: '↻ Riprova',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => ref.read(alertRulesProvider.notifier).reload(),
            ),
          ],
        );
      }
      return const EmptyState(message: 'Nessuna regola di alert configurata.');
    }
    return context.isDrawerLayout
        ? _alertRulesCards(rules)
        : _alertRulesTable(rules);
  }

  Widget _alertRulesTable(List<AlertRule> rules) {
    final AppTokens t = context.tokens;
    const List<_SettingsColumn> columns = <_SettingsColumn>[
      _SettingsColumn('Ticker', flex: 2),
      _SettingsColumn('Direzione', flex: 2),
      _SettingsColumn('Soglia %', flex: 2),
      _SettingsColumn('Stato', flex: 2),
      _SettingsColumn('Azioni', width: 90, align: TextAlign.center),
    ];
    return _responsiveTable(
      columns: columns,
      minWidth: 560,
      rows: <TableRow>[
        for (final AlertRule rule in rules)
          TableRow(
            children: <Widget>[
              _cell(
                Text(
                  rule.ticker,
                  style: AppText.mono(
                    context,
                    size: 13.1,
                    weight: FontWeight.w700,
                    color: t.primary,
                  ),
                ),
              ),
              _cell(AlertDirectionBadge(direction: rule.direction)),
              _cell(
                Text(
                  '${formatThresholdPercent(alertThresholdValue(rule))}%',
                  style: AppText.mono(
                    context,
                    size: 13.1,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              _cell(
                AppBadge(
                  label: rule.active ? 'Attivo' : 'Inattivo',
                  tone: rule.active ? BadgeTone.success : BadgeTone.danger,
                ),
              ),
              _cell(
                Align(
                  alignment: Alignment.center,
                  child: AppIconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Elimina regola',
                    size: 28,
                    iconSize: 15,
                    bordered: false,
                    danger: true,
                    onPressed: () => _deleteAlertRule(rule),
                  ),
                ),
                align: TextAlign.center,
              ),
            ],
          ),
      ],
    );
  }

  Widget _alertRulesCards(List<AlertRule> rules) {
    return Column(
      children: <Widget>[
        for (final AlertRule rule in rules)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.s8),
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              border: Border.all(color: context.tokens.border),
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            rule.ticker,
                            style: AppText.mono(
                              context,
                              size: 13.1,
                              weight: FontWeight.w700,
                              color: context.tokens.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          AlertDirectionBadge(direction: rule.direction),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s6),
                      Text(
                        'Soglia: '
                        '${formatThresholdPercent(alertThresholdValue(rule))}%'
                        ' • ${rule.active ? 'Attivo' : 'Inattivo'}',
                        style: AppText.caption(context),
                      ),
                    ],
                  ),
                ),
                AppIconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Elimina regola',
                  size: 28,
                  iconSize: 15,
                  bordered: false,
                  danger: true,
                  onPressed: () => _deleteAlertRule(rule),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 5. Sicurezza & password
  // -------------------------------------------------------------------------

  Widget _securitySection() {
    final Widget currentField = _LabeledControl(
      label: 'Password Attuale',
      child: TextField(
        controller: _currentPasswordController,
        obscureText: true,
        autofillHints: const <String>[AutofillHints.password],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(hintText: '••••••••'),
      ),
    );
    final Widget newField = _LabeledControl(
      label: 'Nuova Password (min. 8 car.)',
      child: TextField(
        controller: _newPasswordController,
        obscureText: true,
        autofillHints: const <String>[AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: (String _) => _changePassword(),
        decoration: const InputDecoration(hintText: '••••••••'),
      ),
    );
    final Widget updateButton = AppButton(
      label: 'Aggiorna',
      loading: _changingPassword,
      onPressed: _changePassword,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: '🔒 Sicurezza & Password'),
          if (_passwordError != null) ...<Widget>[
            _ErrorAlert(message: _passwordError!),
            const SizedBox(height: AppSpacing.s14),
          ],
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    currentField,
                    const SizedBox(height: AppSpacing.s12),
                    newField,
                    const SizedBox(height: AppSpacing.s14),
                    Align(alignment: Alignment.centerLeft, child: updateButton),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(child: currentField),
                  const SizedBox(width: AppSpacing.s14),
                  Expanded(child: newField),
                  const SizedBox(width: AppSpacing.s14),
                  updateButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 6. Gestione utenti (admin)
  // -------------------------------------------------------------------------

  Widget _adminUsersSection(AsyncValue<List<AuthUser>> usersAsync) {
    final AppTokens t = context.tokens;
    final AuthUser? me = ref.read(authControllerProvider).value?.user;
    final List<AuthUser> users = usersAsync.value ?? const <AuthUser>[];

    final Widget usernameField = _LabeledControl(
      label: 'Nome Utente',
      child: TextField(
        controller: _newUsernameController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(hintText: 'Es. mario'),
      ),
    );
    final Widget passwordField = _LabeledControl(
      label: 'Password (min. 8 car.)',
      child: TextField(
        controller: _newUserPasswordController,
        obscureText: true,
        autofillHints: const <String>[AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: (String _) => _createUser(),
        decoration: const InputDecoration(hintText: '••••••••'),
      ),
    );
    final Widget adminCheckbox = SizedBox(
      height: 38,
      child: Row(
        children: <Widget>[
          Checkbox(
            value: _newUserIsAdmin,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (bool? value) =>
                setState(() => _newUserIsAdmin = value ?? false),
          ),
          const SizedBox(width: AppSpacing.s6),
          Text('Admin', style: AppText.small(context)),
        ],
      ),
    );
    final Widget createButton = AppButton(
      label: 'Crea Utente',
      loading: _creatingUser,
      loadingLabel: 'Creazione...',
      onPressed: _createUser,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: '👥 Gestione Utenti (Solo Amministratore)',
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: t.surfaceHover,
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '➕ Crea Nuovo Utente',
                  style: AppText.small(context)
                      .copyWith(color: t.primary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.s12),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    if (constraints.maxWidth < AppBreakpoints.drawer) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          usernameField,
                          const SizedBox(height: AppSpacing.s12),
                          passwordField,
                          const SizedBox(height: AppSpacing.s12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: adminCheckbox,
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: createButton,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(child: usernameField),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(child: passwordField),
                        const SizedBox(width: AppSpacing.s12),
                        adminCheckbox,
                        const SizedBox(width: AppSpacing.s12),
                        createButton,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _buildUsersContent(usersAsync, users, me),
        ],
      ),
    );
  }

  Widget _buildUsersContent(
    AsyncValue<List<AuthUser>> usersAsync,
    List<AuthUser> users,
    AuthUser? me,
  ) {
    if (users.isEmpty) {
      if (usersAsync.isLoading) {
        return const Column(
          children: <Widget>[SkeletonRow(), SkeletonRow(), SkeletonRow()],
        );
      }
      if (usersAsync.hasError) {
        return EmptyState(
          icon: const Icon(Icons.error_outline),
          message: 'Errore nel caricamento degli utenti.',
          actions: <Widget>[
            AppButton(
              label: '↻ Riprova',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => ref.read(usersProvider.notifier).reload(),
            ),
          ],
        );
      }
      return const EmptyState(
        message: 'Nessun utente registrato oltre all\'amministratore.',
      );
    }
    return context.isDrawerLayout
        ? _usersCards(users, me)
        : _usersTable(users, me);
  }

  Widget _usersTable(List<AuthUser> users, AuthUser? me) {
    final AppTokens t = context.tokens;
    const List<_SettingsColumn> columns = <_SettingsColumn>[
      _SettingsColumn('Nome Utente', flex: 3),
      _SettingsColumn('Ruolo', flex: 3),
      _SettingsColumn('Data Creazione', flex: 2),
      _SettingsColumn('Ultimo Accesso', flex: 2),
      _SettingsColumn('Azioni', width: 100, align: TextAlign.center),
    ];
    return _responsiveTable(
      columns: columns,
      minWidth: 720,
      rows: <TableRow>[
        for (final AuthUser user in users)
          TableRow(
            children: <Widget>[
              _cell(
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        user.username,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.small(context).copyWith(
                          fontWeight: FontWeight.w700,
                          color: user.isAdmin ? t.primary : t.textPrimary,
                        ),
                      ),
                    ),
                    if (user.id == me?.id)
                      Text(' (Tu)', style: AppText.caption(context)),
                  ],
                ),
              ),
              _cell(_roleBadge(user.isAdmin)),
              _cell(
                Text(
                  formatDate(user.createdAt),
                  style: AppText.small(context)
                      .copyWith(color: t.textSecondary),
                ),
              ),
              _cell(
                Text(
                  user.lastLogin == null ? 'Mai' : formatDate(user.lastLogin),
                  style: AppText.small(context)
                      .copyWith(color: t.textSecondary),
                ),
              ),
              _cell(
                _userActions(user, me, compact: true),
                align: TextAlign.center,
              ),
            ],
          ),
      ],
    );
  }

  Widget _usersCards(List<AuthUser> users, AuthUser? me) {
    final AppTokens t = context.tokens;
    return Column(
      children: <Widget>[
        for (final AuthUser user in users)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.s8),
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(AppRadii.input),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              user.username,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.small(context).copyWith(
                                fontWeight: FontWeight.w700,
                                color: user.isAdmin ? t.primary : t.textPrimary,
                              ),
                            ),
                          ),
                          if (user.id == me?.id)
                            Text(' (Tu)', style: AppText.caption(context)),
                        ],
                      ),
                    ),
                    _roleBadge(user.isAdmin),
                  ],
                ),
                const SizedBox(height: AppSpacing.s6),
                Text(
                  'Creato: ${formatDate(user.createdAt)} • '
                  'Ultimo accesso: '
                  '${user.lastLogin == null ? 'Mai' : formatDate(user.lastLogin)}',
                  style: AppText.caption(context),
                ),
                const SizedBox(height: AppSpacing.s8),
                _userActions(user, me, compact: false),
              ],
            ),
          ),
      ],
    );
  }

  Widget _roleBadge(bool isAdmin) {
    return isAdmin
        ? const AppBadge(label: '👑 Amministratore', tone: BadgeTone.purple)
        : const AppBadge(label: '👤 Utente', tone: BadgeTone.warning);
  }

  /// Azioni di riga utente.
  ///
  /// In tabella (colonna Azioni stretta) il reset password è un bottone icona
  /// con tooltip; nelle card responsive è un bottone etichettato. Il delete è
  /// nascosto per l'utente corrente (sostituito da `-`).
  Widget _userActions(AuthUser user, AuthUser? me, {required bool compact}) {
    final bool isSelf = user.id == me?.id;
    final Widget reset = compact
        ? AppIconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: '🔑 Reimposta password',
            semanticLabel: 'Reimposta password di ${user.username}',
            size: 28,
            iconSize: 15,
            bordered: false,
            onPressed: () => showResetPasswordDialog(context, user),
          )
        : AppButton(
            label: '🔑 Reimposta password',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.xs,
            onPressed: () => showResetPasswordDialog(context, user),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        reset,
        const SizedBox(width: AppSpacing.s4),
        if (isSelf)
          Text('-', style: AppText.caption(context))
        else
          AppIconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Elimina utente',
            semanticLabel: 'Elimina utente ${user.username}',
            size: 28,
            iconSize: 15,
            bordered: false,
            danger: true,
            onPressed: () => _deleteUser(user),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 7. Stato integrazioni
  // -------------------------------------------------------------------------

  Widget _integrationsSection(UserSettings settings) {
    final ApiStatus? status = settings.apiStatus;
    final bool gemini = status?.gemini ?? false;
    final bool telegram = status?.telegram ?? false;
    final String model = (status?.geminiModel.isNotEmpty ?? false)
        ? status!.geminiModel
        : 'gemini-3.7-flash';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: '📡 Stato Integrazioni & Motore AI'),
          Wrap(
            spacing: AppSpacing.s10,
            runSpacing: AppSpacing.s10,
            children: <Widget>[
              _IntegrationCard(
                title: 'Google Gemini AI',
                subtitle: model,
                badge: AppBadge(
                  label: gemini ? '✅ Attivo' : '❌ Non Configurato',
                  tone: gemini ? BadgeTone.success : BadgeTone.danger,
                ),
              ),
              _IntegrationCard(
                title: 'Notizie & Sentiment',
                subtitle: 'Yahoo, Google News, Reddit',
                badge: const AppBadge(
                  label: '✅ Multi-Fonte Attivo',
                  tone: BadgeTone.success,
                ),
              ),
              _IntegrationCard(
                title: 'Bot Telegram',
                subtitle: 'Notifiche push & alert',
                badge: AppBadge(
                  label: telegram ? '✅ Attivo' : '⚪ Opzionale (Off)',
                  tone: telegram ? BadgeTone.success : BadgeTone.neutral,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          Text(
            '💡 Zero configurazioni complesse: Notizie e discussioni di '
            'mercato vengono aggregate automaticamente da più fonti senza '
            'richiedere credenziali sviluppatore Reddit.',
            style: AppText.caption(context),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 8. Server (carryover F8)
  // -------------------------------------------------------------------------

  Widget _serverSection() {
    final AppTokens t = context.tokens;
    final String text = _serverController.text.trim();
    final bool hasText = text.isNotEmpty;
    final bool valid = !hasText || AppConfig.isValidOrigin(text);
    final String normalized = hasText && valid
        ? AppConfig.normalizeOrigin(text)
        : '';
    final bool changed =
        hasText && valid && _serverLoaded && normalized != _currentServer;
    final bool canSave = !kIsWeb && changed && !_serverSaving;

    final Widget explainer = Text(
      kIsWeb
          ? 'Su web il client usa automaticamente la stessa origine che serve '
                'l\'app: l\'indirizzo del server non è modificabile.'
          : 'Indirizzo del backend usato dall\'app (es. '
                'http://192.168.1.10:8000). Il salvataggio azzera la sessione '
                'corrente e richiede un nuovo login.',
      style: AppText.caption(context),
    );

    final Widget currentLabel = Text(
      kIsWeb
          ? 'Origine corrente: $_currentServer'
          : _currentServer.isEmpty
          ? 'Server corrente: non configurato'
          : 'Server corrente: $_currentServer',
      style: AppText.caption(context).copyWith(
        fontFamily: AppTokens.monoFontFamily,
        fontFamilyFallback: AppTokens.monoFontFallback,
      ),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(
            title: '🖥️ Server',
            subtitle: 'Connessione al backend di Stock Monitor',
          ),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget field = _LabeledControl(
                label: 'Indirizzo Server',
                child: TextField(
                  controller: _serverController,
                  enabled: !kIsWeb,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (String _) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'http://192.168.1.10:8000',
                    errorText: valid
                        ? null
                        : 'Inserisci un indirizzo valido '
                              '(es. http://192.168.1.10:8000)',
                  ),
                ),
              );
              final Widget saveButton = AppButton(
                label: 'Salva Indirizzo',
                loading: _serverSaving,
                onPressed: canSave ? _saveServer : null,
              );

              if (constraints.maxWidth < AppBreakpoints.compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    field,
                    const SizedBox(height: AppSpacing.s12),
                    Align(alignment: Alignment.centerLeft, child: saveButton),
                    const SizedBox(height: AppSpacing.s10),
                    explainer,
                    const SizedBox(height: AppSpacing.s6),
                    currentLabel,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: field),
                      const SizedBox(width: AppSpacing.s14),
                      saveButton,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s10),
                  explainer,
                  const SizedBox(height: AppSpacing.s6),
                  currentLabel,
                ],
              );
            },
          ),
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: Text(
                'Il campo è disabilitato: la build web è servita '
                'direttamente dal backend.',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11.2,
                  height: 1.4,
                  fontFamilyFallback: AppTokens.fontFallback,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tabella responsive condivisa
  // -------------------------------------------------------------------------

  Widget _responsiveTable({
    required List<_SettingsColumn> columns,
    required List<TableRow> rows,
    double minWidth = 560,
  }) {
    final AppTokens t = context.tokens;
    final Table table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: <int, TableColumnWidth>{
        for (var i = 0; i < columns.length; i++)
          i: columns[i].width != null
              ? FixedColumnWidth(columns[i].width!)
              : FlexColumnWidth(columns[i].flex),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: t.borderSubtle),
        bottom: BorderSide(color: t.border),
      ),
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            for (final _SettingsColumn column in columns)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s10,
                  vertical: AppSpacing.s8,
                ),
                child: Text(
                  column.label.toUpperCase(),
                  textAlign: column.align,
                  style: AppText.tableHeader(context),
                ),
              ),
          ],
        ),
        ...rows,
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < minWidth) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: minWidth, child: table),
          );
        }
        return table;
      },
    );
  }

  Widget _cell(Widget child, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s10,
      ),
      child: Align(alignment: _alignmentFor(align), child: child),
    );
  }

  static Alignment _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  static double? _parseDecimal(String raw) {
    final String value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }
}

/// Preset del budget: etichetta già formattata `it-IT` e valore.
const List<(String, double)> _budgetPresets = <(String, double)>[
  ('2.500 €', 2500),
  ('5.000 €', 5000),
  ('10.000 €', 10000),
  ('25.000 €', 25000),
  ('50.000 €', 50000),
];

/// Campo con etichetta sopra (`.form-group`): label + gap 6.
class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppText.formLabel(context)),
        const SizedBox(height: AppSpacing.s6),
        child,
      ],
    );
  }
}

/// Alert inline di errore (`.alert-error`): sfondo/bordo danger e live region.
class _ErrorAlert extends StatelessWidget {
  const _ErrorAlert({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.dangerBg,
          border: Border.all(color: t.dangerBorder),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('⚠️', style: TextStyle(fontSize: 14, height: 1.4)),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: t.danger,
                  fontSize: 13.6,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  fontFamilyFallback: AppTokens.fontFallback,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox con etichetta cliccabile (`.flex items-center gap-2`).
class _MarketCheckbox extends StatelessWidget {
  const _MarketCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Checkbox(
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (bool? next) => onChanged(next ?? false),
          ),
          const SizedBox(width: AppSpacing.s6),
          Text(label, style: AppText.small(context)),
        ],
      ),
    );
  }
}

/// Campo orario con etichetta (`input-time`, larghezza 118).
class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppText.caption(context)),
        const SizedBox(height: AppSpacing.s4),
        SizedBox(
          width: 118,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.datetime,
            textInputAction: TextInputAction.next,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
              LengthLimitingTextInputFormatter(5),
            ],
            decoration: const InputDecoration(hintText: 'HH:MM'),
          ),
        ),
      ],
    );
  }
}

/// Card di stato di un'integrazione (`.integration-card`).
class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  final String title;
  final String subtitle;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final double width = context.isCompact ? double.infinity : 260;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: t.surfaceHover,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: AppText.small(context)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(subtitle, style: AppText.caption(context)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s10),
            // Il badge resta a dimensione intrinseca ma, su card strette o
            // label lunghe, si riduce invece di sbordare.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: badge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge della direzione di una regola alert: UP verde, DOWN rosso,
/// BOTH ambra (fix #14: il backend ammette anche BOTH).
class AlertDirectionBadge extends StatelessWidget {
  /// Crea il badge per [direction] (`UP`/`DOWN`/`BOTH`).
  const AlertDirectionBadge({super.key, required this.direction});

  /// Direzione della regola.
  final String direction;

  @override
  Widget build(BuildContext context) {
    final String value = direction.toUpperCase();
    return switch (value) {
      'UP' => const AppBadge(label: 'UP', tone: BadgeTone.success),
      'DOWN' => const AppBadge(label: 'DOWN', tone: BadgeTone.danger),
      'BOTH' => const AppBadge(label: 'BOTH', tone: BadgeTone.warning),
      _ => AppBadge(label: value, tone: BadgeTone.neutral),
    };
  }
}

/// Colonna della tabella impostazioni (larghezza fissa o flessibile).
class _SettingsColumn {
  const _SettingsColumn(
    this.label, {
    this.width,
    this.flex = 1,
    this.align = TextAlign.left,
  });

  final String label;
  final double? width;
  final double flex;
  final TextAlign align;
}
