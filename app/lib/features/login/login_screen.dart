import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/session/auth_controller.dart';
import '../../core/session/session_epoch.dart';
import '../../core/storage.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_button.dart';

/// Schermata di login, parità visiva e di copy con `frontend/login.html`:
/// logo 📈, titolo `Stock Monitor`, sottotitolo, campi utente/password con
/// toggle mostra/nascondi, alert errore (`role=alert`), bottone `Accedi` con
/// stato `Verifica in corso...` e badge di sicurezza.
///
/// Su piattaforma non web, quando la build non ha un default `API_BASE_URL`
/// il campo `Indirizzo server` è sempre visibile e prefillato dal valore
/// salvato: resta correggibile anche dopo un salvataggio o un tentativo di
/// login fallito, così un IP errato non può bloccare l'accesso (finché la
/// sezione Impostazioni non offrirà la stessa configurazione). Su web il campo
/// non compare mai. Con `?expired=1` (o sessione scaduta) mostra
/// `Sessione non valida o scaduta. Effettua il login.`.
///
/// Alla creazione consuma l'eventuale [sessionNotice] pendente (segnale fuori
/// scope, es. cambio server) e la mostra una sola volta come alert
/// informativo.
class LoginScreen extends ConsumerStatefulWidget {
  /// Crea la schermata di login.
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _serverController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _showPassword = false;
  bool _submitting = false;
  bool _expiredChecked = false;
  String? _error;
  String? _notice;

  static const String _sessionExpiredMessage =
      'Sessione non valida o scaduta. Effettua il login.';
  static const String _invalidServerMessage =
      'Inserisci un indirizzo valido (es. http://192.168.1.10:8000)';

  @override
  void initState() {
    super.initState();
    // Notice pendente fuori scope (es. cambio server): consumata una sola
    // volta, prima che la ricreazione dello scope la possa perdere.
    _notice = sessionNotice.value;
    sessionNotice.value = null;
    _loadStoredServer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_expiredChecked) return;
    _expiredChecked = true;
    if (_isExpired()) {
      _error = _sessionExpiredMessage;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// True quando la schermata deve mostrare il campo `Indirizzo server`:
  /// piattaforma non web e nessun default di build (`API_BASE_URL`).
  ///
  /// La condizione è stabile per tutta la vita della schermata: il campo non
  /// sparisce mai dopo un salvataggio o un errore di login, altrimenti un URL
  /// errato lascerebbe l'utente senza modo di correggerlo.
  bool get _showServerField =>
      !kIsWeb && AppConfig.apiBaseUrlFromEnv.trim().isEmpty;

  Future<void> _loadStoredServer() async {
    if (kIsWeb) return;
    final String? stored = await ref
        .read(appStorageProvider)
        .getServerBaseUrl();
    // Non sovrascrivere un eventuale testo già digitato dall'utente.
    if (!mounted ||
        stored == null ||
        stored.isEmpty ||
        _serverController.text.isNotEmpty) {
      return;
    }
    setState(() => _serverController.text = stored);
  }

  /// Legge `expired=1` dalla rotta go_router o dall'URL base (fallback web).
  bool _isExpired() {
    final GoRouter? router = GoRouter.maybeOf(context);
    final String? param = router?.state.uri.queryParameters['expired'];
    return param == '1' || Uri.base.queryParameters['expired'] == '1';
  }

  /// Valida un indirizzo server: schema http/https e host non vuoto.
  bool _isValidServerUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text;
    // Come il form HTML: senza credenziali non si parte.
    if (username.isEmpty || password.isEmpty) return;

    final ApiClient client = ref.read(apiClientProvider);
    if (_showServerField) {
      final String server = _serverController.text.trim();
      if (server.isEmpty) {
        // Senza input si usa la configurazione già presente (URL salvata);
        // se manca del tutto lo segnaliamo prima di tentare la rete.
        if (!client.isConfigured) {
          setState(() => _error = _invalidServerMessage);
          return;
        }
      } else if (!_isValidServerUrl(server)) {
        setState(() => _error = _invalidServerMessage);
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_showServerField) {
        final String server = _serverController.text.trim();
        if (server.isNotEmpty) {
          await ref.read(appStorageProvider).setServerBaseUrl(server);
          client.setBaseUrl(server);
        }
      }
      await ref.read(authControllerProvider.notifier).login(username, password);
      // Il redirect post-login è responsabilità del guard del router.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message.isEmpty
            ? 'Credenziali non corrette'
            : error.message;
        _passwordController.clear();
      });
      _passwordFocus.requestFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Credenziali non corrette';
        _passwordController.clear();
      });
      _passwordFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final bool showServerField = _showServerField;
    final bool sessionExpired =
        ref.watch(authControllerProvider).value?.sessionExpired ?? false;
    final String? error =
        _error ?? (sessionExpired ? _sessionExpiredMessage : null);
    // La notice è informativa: lascia precedenza all'eventuale errore.
    final String? notice = error == null ? _notice : null;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _Entrance(
              reduceMotion: reduceMotion,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.border),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    boxShadow: t.shadowMd,
                  ),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          '📈',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30.4, height: 1.2),
                        ),
                        const SizedBox(height: AppSpacing.s6),
                        Text(
                          'Stock Monitor',
                          textAlign: TextAlign.center,
                          style: AppText.loginTitle(context),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          'Accedi alla tua dashboard finanziaria',
                          textAlign: TextAlign.center,
                          style: AppText.loginSubtitle(context),
                        ),
                        const SizedBox(height: AppSpacing.s24),
                        if (error != null) ...<Widget>[
                          _ErrorAlert(message: error),
                          const SizedBox(height: AppSpacing.s16),
                        ] else if (notice != null) ...<Widget>[
                          _NoticeAlert(message: notice),
                          const SizedBox(height: AppSpacing.s16),
                        ],
                        if (showServerField) ...<Widget>[
                          _LabeledField(
                            label: 'Indirizzo server',
                            child: TextField(
                              controller: _serverController,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              style: AppText.body(context)
                                  .copyWith(fontSize: 14.4),
                              decoration: const InputDecoration(
                                hintText: 'http://192.168.1.10:8000',
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s14),
                        ],
                        _LabeledField(
                          label: 'Nome Utente',
                          child: TextField(
                            controller: _usernameController,
                            autofocus: true,
                            autofillHints: const <String>[
                              AutofillHints.username,
                            ],
                            textInputAction: TextInputAction.next,
                            style: AppText.body(context)
                                .copyWith(fontSize: 14.4),
                            decoration: const InputDecoration(
                              hintText: 'Inserisci il tuo nome utente',
                            ),
                            onSubmitted: (String _) =>
                                _passwordFocus.requestFocus(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s14),
                        _LabeledField(
                          label: 'Password',
                          child: TextField(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            obscureText: !_showPassword,
                            autofillHints: const <String>[
                              AutofillHints.password,
                            ],
                            textInputAction: TextInputAction.done,
                            style: AppText.body(context)
                                .copyWith(fontSize: 14.4),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 38,
                                minHeight: 34,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                tooltip: _showPassword
                                    ? 'Nascondi password'
                                    : 'Mostra password',
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 17,
                                ),
                              ),
                            ),
                            onSubmitted: (String _) => _submit(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s20),
                        SizedBox(
                          height: 42,
                          child: AppButton(
                            label: 'Accedi',
                            loading: _submitting,
                            loadingLabel: 'Verifica in corso...',
                            expand: true,
                            onPressed: _submit,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s22),
                        Container(
                          padding: const EdgeInsets.only(top: AppSpacing.s14),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: t.border)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '🔒 Connessione protetta con crittografia bcrypt e JWT',
                            textAlign: TextAlign.center,
                            style: AppText.securityBadge(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Campi con etichetta sopra, come `.form-group` (label `.82rem/600` + gap 5).
class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: AppText.formLabel(context)),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

/// Alert di errore (`.alert-error`): sfondo/bordo danger, `role=alert`
/// equivalente via live region.
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

/// Alert informativo una tantum (es. server cambiato): stessi toni del DS
/// (alone primary), `role=status` equivalente via live region.
class _NoticeAlert extends StatelessWidget {
  const _NoticeAlert({required this.message});

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
          color: t.primaryGlow,
          border: Border.all(color: t.primary),
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline, size: 16, color: t.primary),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: t.primary,
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

/// Entrata `fade-in-up` (0.3s, 6px), disattivata con `prefers-reduced-motion`.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child, required this.reduceMotion});

  final Widget child;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: AppMotion.ease,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
