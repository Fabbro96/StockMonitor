import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_monitor/shell/topbar.dart';

/// Harness minimale: due pagine di test che rivendicano le azioni della topbar.
///
/// La pagina A resta montata mentre B entra (come in una transizione reale),
/// così si verifica che il `clear` della pagina uscente non cancelli le azioni
/// della entrante grazie all'ownership.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _showFirst = true;
  bool _showSecond = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          const _TopbarActionsView(),
          TextButton(
            onPressed: () => setState(() => _showSecond = true),
            child: const Text('mostra-B'),
          ),
          TextButton(
            onPressed: () => setState(() => _showFirst = false),
            child: const Text('smonta-A'),
          ),
          TextButton(
            onPressed: () => setState(() => _showSecond = false),
            child: const Text('smonta-B'),
          ),
          if (_showFirst)
            const _ActionsPage(key: ValueKey<String>('page-A'), id: 'A', actionLabel: 'azione-A'),
          if (_showSecond)
            const _ActionsPage(key: ValueKey<String>('page-B'), id: 'B', actionLabel: 'azione-B'),
        ],
      ),
    );
  }
}

class _TopbarActionsView extends ConsumerWidget {
  const _TopbarActionsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Widget> actions = ref.watch(topbarActionsProvider);
    return Column(children: actions);
  }
}

class _ActionsPage extends ConsumerStatefulWidget {
  const _ActionsPage({super.key, required this.id, required this.actionLabel});

  final String id;
  final String actionLabel;

  @override
  ConsumerState<_ActionsPage> createState() => _ActionsPageState();
}

class _ActionsPageState extends ConsumerState<_ActionsPage> {
  late final TopbarActionsController _topbar;

  @override
  void initState() {
    super.initState();
    _topbar = ref.read(topbarActionsProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      _topbar.set(this, <Widget>[Text(widget.actionLabel)]);
    });
  }

  @override
  void dispose() {
    // Campo catturato, non `ref`: il clear va fatto qui senza toccare il ref
    // di un widget ormai smontato.
    _topbar.clear(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('pagina-${widget.id}');
}

void main() {
  testWidgets('set post-frame, ownership del clear, azzeramento', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: _Harness())));

    // (a) set() eseguito in post-frame callback: le azioni compaiono.
    await tester.pump();
    await tester.pump();
    expect(find.text('azione-A'), findsOneWidget);
    expect(find.text('azione-B'), findsNothing);

    // B entra mentre A è ancora montata: B diventa il proprietario.
    await tester.tap(find.text('mostra-B'));
    await tester.pump();
    await tester.pump();
    expect(find.text('azione-B'), findsOneWidget);
    expect(find.text('azione-A'), findsNothing);

    // (b) A viene smontata dopo B: il suo clear(this) non deve cancellare le
    // azioni della pagina entrante (ownership).
    await tester.tap(find.text('smonta-A'));
    await tester.pump();
    await tester.pump();
    expect(find.text('azione-B'), findsOneWidget);

    // (c) il clear del proprietario corrente azzera davvero le azioni.
    await tester.tap(find.text('smonta-B'));
    await tester.pump();
    await tester.pump();
    expect(find.text('azione-B'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
