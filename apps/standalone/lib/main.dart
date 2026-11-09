import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dartchess/dartchess.dart';
import 'package:trainer_core/trainer_core.dart';
import 'package:trainer_lichess/trainer_lichess.dart';
import 'package:trainer_lichess/connection.dart';
import 'package:study_trainer/auth.dart';
import 'package:trainer_flutter/trainer_flutter.dart';
import 'package:trainer_storage/trainer_storage.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TrainerBootstrap(openStore: openAppStore));
}

Future<TrainerStore> openAppStore() async {
  final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  if (desktop) sqfliteFfiInit();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return SqliteTrainerStore.open(
    desktop ? databaseFactoryFfi : mobile.databaseFactory,
    '${dir.path}/trainer.sqlite',
  );
}

/// Failed migrations or disk errors must produce a recoverable screen rather
/// than an unhandled startup exception. Opening never deletes an existing DB.
class TrainerBootstrap extends StatefulWidget {
  const TrainerBootstrap({super.key, required this.openStore});
  final Future<TrainerStore> Function() openStore;
  @override
  State<TrainerBootstrap> createState() => _TrainerBootstrapState();
}

class _TrainerBootstrapState extends State<TrainerBootstrap> {
  TrainerStore? store;
  bool failed = false, loading = true;
  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result = await widget.openStore();
      if (mounted) setState(() => store = result);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (store != null) return TrainerApp(store: store!);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Study Trainer')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading) const CircularProgressIndicator(),
                  if (failed) ...[
                    const Text(
                      'Local training data could not be opened. Check available device storage and retry.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: open,
                      child: const Text('Retry opening library'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrainerApp extends StatefulWidget {
  const TrainerApp({super.key, required this.store});
  final TrainerStore store;
  @override
  State<TrainerApp> createState() => _TrainerAppState();
}

class _TrainerAppState extends State<TrainerApp> {
  bool dark = true;
  @override
  void initState() {
    super.initState();
    restoreTheme();
  }

  Future<void> restoreTheme() async {
    try {
      final saved = await widget.store.setting('dark');
      if (mounted && saved != null) setState(() => dark = saved == 'true');
    } catch (_) {
      /* Library recovery reports storage failures. */
    }
  }

  Future<void> toggleTheme() async {
    try {
      await widget.store.setSetting('dark', '${!dark}');
      if (mounted) setState(() => dark = !dark);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not save appearance')),
        );
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Study Trainer',
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff629924)),
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff629924),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff262421),
    ),
    home: Home(store: widget.store, onTheme: toggleTheme),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, required this.store, required this.onTheme});
  final TrainerStore store;
  final VoidCallback onTheme;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Decision> items = [];
  List<SourceSummary> sources = [];
  bool autoReply = true;
  Map<String, ReviewState> states = {};
  List<Decision>? queue;
  TrainingSession? session;
  List<ReviewEvent> history = [];
  double retention = .9;
  int index = 0, tab = 0, newLimit = 20, reviewLimit = 100;
  bool busy = false;
  Side side = Side.white;
  String message = '';
  final network = http.Client();
  final mobileAuth = Platform.isAndroid || Platform.isIOS;
  late final connection = LichessConnection(
    inner: network,
    vault: const SecureTokenVault(),
    authorize: authorizeLichess,
  );
  late final studyClient = LichessStudyClient(connection);
  final pgn = TextEditingController(),
      source = TextEditingController(text: 'local:repertoire');
  @override
  void initState() {
    super.initState();
    action(() async {
      await recover();
      if (mobileAuth) await connection.restore();
    });
  }

  @override
  void dispose() {
    pgn.dispose();
    source.dispose();
    network.close();
    super.dispose();
  }

  Future<void> recover() async {
    await load();
    final saved = await widget.store.setting('session');
    final newValue = await widget.store.setting('newLimit');
    final reviewValue = await widget.store.setting('reviewLimit');
    final retentionValue = await widget.store.setting('retention');
    final sideValue = await widget.store.setting('side');
    final replyValue = await widget.store.setting('autoReply');
    if (!mounted) return;
    final active = saved == null ? null : TrainingSession.decode(saved);
    // Removed source decisions cannot be reviewed after refresh.
    final available = items.map((d) => d.id).toSet();
    final repaired = active == null
        ? null
        : TrainingSession(
            token: active.token,
            remaining: active.remaining.where(available.contains),
            attempts: active.attempts,
          );
    if (repaired != null)
      await widget.store.setSetting('session', repaired.encode());
    if (!mounted) return;
    setState(() {
      newLimit = int.tryParse(newValue ?? '') ?? 20;
      reviewLimit = int.tryParse(reviewValue ?? '') ?? 100;
      retention = double.tryParse(retentionValue ?? '') ?? .9;
      side = sideValue == 'black' ? Side.black : Side.white;
      autoReply = replyValue != 'false';
      session = repaired;
      queue = repaired == null || repaired.remaining.isEmpty
          ? null
          : [
              for (final id in repaired.remaining)
                items.firstWhere((d) => d.id == id),
            ];
      index = 0;
    });
  }

  Future<void> load() async {
    final i = await widget.store.decisions();
    final s = await widget.store.states();
    final h = await widget.store.history();
    final snapshots = await widget.store.sources();
    if (mounted)
      setState(() {
        items = i;
        states = s;
        history = h;
        sources = snapshots;
      });
  }

  Future<void> action(Future<void> Function() f) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await f();
      await load();
      if (mounted) setState(() => message = 'Saved locally');
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    String text = pgn.text, id = source.text.trim();
    final uri = Uri.tryParse(id);
    if (uri != null && uri.scheme == 'https') {
      final parsed = StudySource.url(id);
      text = await studyClient.download(parsed);
      id = parsed.id;
    }
    if (id.isEmpty)
      throw const FormatException('Source identifier is required');
    final result = await compute(parseImport, (text, id));
    await widget.store.replaceSource(id, result);
  }

  Future<void> refreshSource(String id) async {
    final remote = StudySource.fromId(id);
    final text = await studyClient.download(remote);
    final result = await compute(parseImport, (text, id));
    await widget.store.replaceSource(id, result);
  }

  Future<void> editLocalSource(String id) async {
    final cached = await widget.store.source(id);
    if (cached == null) throw StateError('Source no longer exists');
    source.text = id;
    pgn.text = cached.pgn;
    if (mounted) setState(() => tab = 1);
  }

  Future<void> setSide(Side value) async {
    await widget.store.setSetting('side', value.name);
    if (mounted) setState(() => side = value);
  }

  Future<void> start({
    String? chapter,
    String? study,
    bool mistakes = false,
    bool scheduled = false,
  }) async {
    final now = DateTime.now();
    final selected = trainingQueue(
      decisions: items,
      states: states,
      today: history.where((e) => e.day == reviewDay(now)),
      outcomes: history,
      now: now.toUtc(),
      newLimit: newLimit,
      reviewLimit: reviewLimit,
      dueOnly: scheduled,
      mistakesOnly: mistakes,
      source: study,
      chapter: chapter,
      side: side,
    );
    final token = identity([
      now.microsecondsSinceEpoch,
      Random.secure().nextInt(1 << 32),
    ]);
    final active = TrainingSession(
      token: token,
      remaining: selected.map((d) => d.id),
      attempts: session?.attempts ?? const {},
    );
    await widget.store.setSetting('session', active.encode());
    if (mounted)
      setState(() {
        session = active;
        queue = selected;
        index = 0;
      });
  }

  Future<void> attempt(AttemptEvidence evidence) async {
    final active = session!;
    final updated = await widget.store.recordAttempt(
      active.token,
      queue![index].id,
      evidence,
    );
    if (mounted && session?.token == active.token)
      setState(() => session = updated);
  }

  Future<void> complete(Rating rating) async {
    final active = session!;
    final d = queue![index];
    final result = schedule(
      states[d.id],
      rating,
      DateTime.now(),
      retention: retention,
      decision: d,
    );
    final next = active.advance();
    await widget.store.review(
      active.eventId(d.id),
      d.id,
      ScheduledReview(
        result.state,
        result.log,
        previousReview: result.previousReview,
        decisionRevision: result.decisionRevision,
        session: next.encode(),
      ),
    );
    // Advance immediately after the durable commit. A failed dashboard refresh
    // must not leave an already-completed decision available for another grade.
    if (mounted && session?.token == active.token)
      setState(() {
        session = next;
        index++;
      });
    try {
      await load();
    } catch (e) {
      if (mounted)
        setState(
          () => message = 'Review saved. Could not refresh progress: $e',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.where((d) => d.side == side).toList();
    final due = visibleItems
        .where(
          (d) =>
              states[d.id] != null &&
              !states[d.id]!.card.due.isAfter(DateTime.now().toUtc()),
        )
        .length;
    final stats = ReviewStatistics(history);
    final today = reviewDay(DateTime.now());
    final budget = DailyBudget(
      history.where((e) => e.day == today),
      newLimit: newLimit,
      reviewLimit: reviewLimit,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Trainer'),
        actions: [
          IconButton(
            onPressed: widget.onTheme,
            icon: const Icon(Icons.brightness_6),
            tooltip: 'Appearance',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (message.isNotEmpty) Text(message),
                if (busy) const LinearProgressIndicator(),
                if (queue != null) ...[
                  Text(
                    'Review ${min(index + 1, queue!.length)} / ${queue!.length}',
                  ),
                  if (index < queue!.length)
                    TrainingBoard(
                      key: ValueKey(queue![index].id),
                      decision: queue![index],
                      initialEvidence: session!.evidence(queue![index].id),
                      onAttemptChanged: attempt,
                      onComplete: complete,
                      playOpponentReply: autoReply,
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Session complete. Progress saved.'),
                    ),
                  TextButton(
                    onPressed: () => setState(() => queue = null),
                    child: const Text('Return to library'),
                  ),
                ] else if (tab == 0) ...[
                  Text(
                    'Your daily practice',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  DropdownButton<Side>(
                    key: const ValueKey('trainingSide'),
                    value: side,
                    items: Side.values
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text('Train ${s.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) => action(() => setSide(value!)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$due due · ${visibleItems.where((d) => !states.containsKey(d.id)).length} new decisions',
                  ),
                  Text(
                    'Today: ${budget.newRemaining} new slots · ${budget.reviewRemaining} review slots remaining',
                  ),
                  if (session != null && session!.remaining.isNotEmpty)
                    TextButton(
                      onPressed: () => action(recover),
                      child: const Text('Resume unfinished session'),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => action(() => start(scheduled: true)),
                    child: const Text('Start due reviews'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(() => start(mistakes: true)),
                    child: const Text('Review mistakes'),
                  ),
                  const Divider(),
                  for (final snapshot in sources)
                    ExpansionTile(
                      key: ValueKey('source:${snapshot.id}'),
                      title: Text(snapshot.id),
                      subtitle: Text(
                        'Available offline${snapshot.importedAt == null ? '' : ' · Updated ${snapshot.importedAt!.toLocal()}'}',
                      ),
                      children: [
                        if (snapshot.id.startsWith('lichess:'))
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () =>
                                      action(() => refreshSource(snapshot.id)),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh from Lichess'),
                          )
                        else
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () => action(
                                    () => editLocalSource(snapshot.id),
                                  ),
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit / reimport PGN'),
                          ),
                        ListTile(
                          title: const Text('Practice study'),
                          onTap: busy
                              ? null
                              : () => action(() => start(study: snapshot.id)),
                        ),
                        for (final chapter
                            in items
                                .where((d) => d.source == snapshot.id)
                                .map((d) => d.chapter)
                                .toSet())
                          ListTile(
                            title: Text(
                              items
                                  .firstWhere(
                                    (d) =>
                                        d.source == snapshot.id &&
                                        d.chapter == chapter,
                                  )
                                  .title,
                            ),
                            subtitle: Text(
                              '${visibleItems.where((d) => d.source == snapshot.id && d.chapter == chapter).length} ${side.name} decisions',
                            ),
                            onTap: busy
                                ? null
                                : () => action(
                                    () => start(
                                      study: snapshot.id,
                                      chapter: chapter,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                ] else if (tab == 1) ...[
                  Text(
                    'Import or refresh',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  TextField(
                    controller: source,
                    decoration: const InputDecoration(
                      labelText: 'Study URL or stable local source ID',
                    ),
                  ),
                  DropdownButton<Side>(
                    value: side,
                    items: Side.values
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text('Train ${s.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (s) => action(() async {
                            await setSide(s!);
                          }),
                  ),
                  TextField(
                    controller: pgn,
                    minLines: 5,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Paste PGN (multiple chapters supported)',
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action(() async {
                            final result = await FilePicker.pickFile();
                            if (result != null)
                              pgn.text = utf8.decode(
                                await result.readAsBytes(),
                              );
                          }),
                    child: const Text('Open PGN file'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => action(import),
                    child: const Text('Import / refresh same source'),
                  ),
                  const Text(
                    'Connect in Settings to import private studies. Keep local source IDs and chapter Event names stable on refresh.',
                  ),
                ] else if (tab == 2) ...[
                  Text(
                    'Progress',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    '${items.where((d) => states.containsKey(d.id)).length} studied decisions · $due due',
                  ),
                  Text(
                    '${stats.completed} completed reviews · ${stats.accuracy == null ? 'No reviews yet' : '${(stats.accuracy! * 100).toStringAsFixed(1)}% unassisted recall'}',
                  ),
                  Text(
                    '${stats.hinted} hinted reviews · ${stats.mistakes} wrong moves',
                  ),
                  for (final source in history.map((e) => e.source).toSet())
                    ListTile(
                      title: Text(source),
                      subtitle: Text(
                        '${history.where((e) => e.source == source).length} completed reviews',
                      ),
                    ),
                  const Divider(),
                  const Text('Recent review history'),
                  for (final e in history.reversed.take(30))
                    ListTile(
                      title: Text('${e.rating.name} · ${e.source}'),
                      subtitle: Text(
                        '${e.at.toLocal()} · ${e.evidence.hinted
                            ? 'hint used'
                            : e.evidence.mistakes > 0
                            ? '${e.evidence.mistakes} mistakes'
                            : 'unassisted'}',
                      ),
                    ),
                  const Divider(),
                  const Text('Upcoming decisions'),
                  for (final d in items.where((d) => states.containsKey(d.id)))
                    ListTile(
                      title: Text(d.title),
                      subtitle: Text(
                        'Next review: ${states[d.id]!.card.due.toLocal()}',
                      ),
                    ),
                ] else ...[
                  Text(
                    'Settings & backups',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  ListTile(
                    title: const Text('Lichess connection'),
                    subtitle: Text(connection.username ?? 'Not connected'),
                  ),
                  if (mobileAuth) ...[
                    if (!connection.connected)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => action(connection.connect),
                        child: const Text('Connect to Lichess'),
                      ),
                    if (connection.connected) ...[
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => action(() => connection.disconnect()),
                        child: const Text('Revoke and disconnect'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => action(
                                () => connection.disconnect(revoke: false),
                              ),
                        child: const Text('Disconnect this device only'),
                      ),
                    ],
                  ] else
                    const Text(
                      'Account connection is available on Android and iOS. Public studies and local PGN work here.',
                    ),
                  ListTile(
                    title: Text('New items per day: $newLimit'),
                    trailing: DropdownButton<int>(
                      value: newLimit,
                      items: ({0, 10, 20, 50, newLimit}.toList()..sort())
                          .map(
                            (n) =>
                                DropdownMenuItem(value: n, child: Text('$n')),
                          )
                          .toList(),
                      onChanged: (n) => action(() async {
                        await widget.store.setSetting('newLimit', '$n');
                        setState(() => newLimit = n!);
                      }),
                    ),
                  ),
                  ListTile(
                    title: const Text('Review items per day'),
                    trailing: DropdownButton<int>(
                      value: reviewLimit,
                      items:
                          ({0, 20, 50, 100, 200, reviewLimit}.toList()..sort())
                              .map(
                                (n) => DropdownMenuItem(
                                  value: n,
                                  child: Text('$n'),
                                ),
                              )
                              .toList(),
                      onChanged: busy
                          ? null
                          : (n) => action(() async {
                              await widget.store.setSetting(
                                'reviewLimit',
                                '$n',
                              );
                              if (mounted) setState(() => reviewLimit = n!);
                            }),
                    ),
                  ),
                  ListTile(
                    title: const Text('Desired retention'),
                    trailing: DropdownButton<double>(
                      value: retention,
                      items: ({.8, .85, .9, .95, retention}.toList()..sort())
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text('${(n * 100).round()}%'),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (n) => action(() async {
                              await widget.store.setSetting('retention', '$n');
                              if (mounted) setState(() => retention = n!);
                            }),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Play an opponent reply after a correct move',
                    ),
                    value: autoReply,
                    onChanged: busy
                        ? null
                        : (value) => action(() async {
                            await widget.store.setSetting(
                              'autoReply',
                              '$value',
                            );
                            if (mounted) setState(() => autoReply = value);
                          }),
                  ),
                  const Text(
                    'Limits are shared by White and Black and count distinct items per local day. Further learning steps for today’s items remain available.',
                  ),
                  TextButton(
                    onPressed: () => action(() async {
                      final bytes = utf8.encode(await widget.store.backup());
                      await FilePicker.saveFile(
                        fileName: 'study-trainer-backup.json',
                        bytes: Uint8List.fromList(bytes),
                      );
                    }),
                    child: const Text('Export full backup'),
                  ),
                  TextButton(
                    onPressed: () => action(() async {
                      final result = await FilePicker.pickFile();
                      if (result != null && mounted) {
                        final accepted = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Replace local training data?'),
                            content: const Text(
                              'This replaces your studies, schedules and review history. Export a backup first.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Replace data'),
                              ),
                            ],
                          ),
                        );
                        if (accepted == true) {
                          await widget.store.restore(
                            utf8.decode(await result.readAsBytes()),
                          );
                          await recover();
                        }
                      }
                    }),
                    child: const Text('Restore backup (replaces library)'),
                  ),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'Study Trainer',
                    ),
                    child: const Text('Open-source licenses'),
                  ),
                  const Text(
                    'Independent GPL-3.0 study trainer. Not endorsed by Lichess. No account or server required.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (n) => setState(() {
          tab = n;
          queue = null;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.school), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.download), label: 'Import'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

ImportResult parseImport((String, String) args) => importPgn(args.$1, args.$2);
