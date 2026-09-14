import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_button.dart';

/// Tipo di toast, mappa 1:1 con `toast-{success|error|info}` del CSS.
enum AppToastType { success, error, info }

/// Mostra un toast globale (`.toast`): in basso a destra su desktop, a tutta
/// larghezza in basso su mobile (<640px).
///
/// - durata 4s per i toast informativi, 15s quando c'è [actionLabel];
/// - hover o focus sospendono il countdown e lo riprendono (5s con azione,
///   2.5s senza), come il `showToast` del frontend;
/// - [onAction] viene chiamata e il toast si chiude;
/// - il messaggio è testo semplice (nessun escaping manuale necessario);
/// - `prefers-reduced-motion` disattiva slide/fade.
void showAppToast(
  BuildContext context, {
  required String message,
  AppToastType type = AppToastType.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  _ToastHost.of(overlay).show(
    _ToastData(
      id: _ToastHost.nextId++,
      message: message,
      type: type,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

class _ToastData {
  _ToastData({
    required this.id,
    required this.message,
    required this.type,
    this.actionLabel,
    this.onAction,
  });

  final int id;
  final String message;
  final AppToastType type;
  final String? actionLabel;
  final VoidCallback? onAction;

  bool get hasAction => actionLabel != null && onAction != null;
}

/// Gestisce una pila di toast per [OverlayState], con una sola [OverlayEntry]
/// condivisa: i toast entrano/escano dalla colonna senza ricreare l'overlay.
class _ToastHost {
  _ToastHost._(this._overlay);

  static final Map<OverlayState, _ToastHost> _hosts = <OverlayState, _ToastHost>{};
  static int nextId = 0;

  static _ToastHost of(OverlayState overlay) {
    _hosts.removeWhere((OverlayState key, _ToastHost value) => !key.mounted);
    return _hosts.putIfAbsent(overlay, () => _ToastHost._(overlay));
  }

  final OverlayState _overlay;
  final ValueNotifier<List<_ToastData>> _items =
      ValueNotifier<List<_ToastData>>(const <_ToastData>[]);
  OverlayEntry? _entry;

  void show(_ToastData data) {
    _entry ??= OverlayEntry(builder: (BuildContext context) => _ToastHostView(host: this));
    _items.value = <_ToastData>[..._items.value, data];
    if (!(_entry?.mounted ?? false)) {
      _overlay.insert(_entry!);
    }
  }

  void remove(_ToastData data) {
    _items.value = _items.value
        .where((_ToastData item) => item.id != data.id)
        .toList(growable: false);
    if (_items.value.isEmpty) {
      final OverlayEntry? entry = _entry;
      _entry = null;
      // La rimozione può arrivare da un callback di animazione: rimuovi dopo
      // il frame corrente per non mutare l'Overlay durante il build.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        entry?.remove();
        entry?.dispose();
      });
    }
  }
}

class _ToastHostView extends StatelessWidget {
  const _ToastHostView({required this.host});

  final _ToastHost host;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    return ValueListenableBuilder<List<_ToastData>>(
      valueListenable: host._items,
      builder: (BuildContext context, List<_ToastData> items, Widget? _) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Positioned(
          left: compact ? 12 : null,
          right: compact ? 12 : 18,
          bottom: compact ? 12 : 18,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: AppSpacing.s8,
                crossAxisAlignment:
                    compact ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
                children: <Widget>[
                  for (final _ToastData data in items)
                    _ToastItem(key: ValueKey<int>(data.id), data: data, host: host),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToastItem extends StatefulWidget {
  const _ToastItem({super.key, required this.data, required this.host});

  final _ToastData data;
  final _ToastHost host;

  @override
  State<_ToastItem> createState() => _ToastItemState();
}

class _ToastItemState extends State<_ToastItem> {
  static const Duration _infoDuration = Duration(seconds: 4);
  static const Duration _actionDuration = Duration(seconds: 15);
  static const Duration _infoResume = Duration(milliseconds: 2500);
  static const Duration _actionResume = Duration(seconds: 5);

  Timer? _timer;
  bool _visible = false;
  bool _dismissed = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || _dismissed) return;
      setState(() => _visible = true);
      _schedule(widget.data.hasAction ? _actionDuration : _infoDuration);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, _dismiss);
  }

  void _pause() => _timer?.cancel();

  void _resume() {
    if (_dismissed) return;
    _schedule(widget.data.hasAction ? _actionResume : _infoResume);
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _timer?.cancel();
    if (_reduceMotion) {
      widget.host.remove(widget.data);
      return;
    }
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens t = context.tokens;
    final Color accent = switch (widget.data.type) {
      AppToastType.success => t.success,
      AppToastType.error => t.danger,
      AppToastType.info => t.primary,
    };
    final Duration duration = _reduceMotion ? Duration.zero : AppMotion.overlay;

    // Accent bar sinistro come striscia clippata su Stack: un Border con lati
    // di colori diversi non è compatibile con borderRadius (assert a ogni
    // paint). Stessa tecnica di AppCard.accent.
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(widget.data.message, style: AppText.toast(context)),
          ),
          if (widget.data.hasAction)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s10),
              child: AppButton(
                label: widget.data.actionLabel!,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: () {
                  widget.data.onAction?.call();
                  _dismiss();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.s6),
            child: AppIconButton(
              icon: const Icon(Icons.close),
              size: 22,
              iconSize: 15,
              bordered: false,
              tooltip: 'Chiudi notifica',
              onPressed: _dismiss,
            ),
          ),
        ],
      ),
    );

    final Widget toast = Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppRadii.input),
        boxShadow: t.shadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          content,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: accent),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => _pause(),
      onExit: (_) => _resume(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (bool hasFocus) => hasFocus ? _pause() : _resume(),
        child: AnimatedSlide(
          offset: _visible ? Offset.zero : const Offset(0, 0.25),
          duration: duration,
          curve: AppMotion.ease,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: duration,
            onEnd: () {
              if (!_visible && !_reduceMotion) {
                widget.host.remove(widget.data);
              }
            },
            child: toast,
          ),
        ),
      ),
    );
  }
}
