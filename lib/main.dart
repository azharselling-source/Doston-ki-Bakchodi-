import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// ====== YAHAN APNI VALUES DAALO (README.md dekho) ======
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDQ7U-YGwb6Mge7mkB8R6fJI5fe6OzkrKI',
  appId: '1:427247595496:android:f5f0544db3ab00716cfe5d',
  messagingSenderId: '427247595496',
  projectId: 'doston-ka-ghar-8fe70',
);
// Naye dost isi code se account bana sakte hain. Isko badal lo.
const groupCode = 'ghar2026';
// =======================================================

const palette = <Color>[
  Color(0xFFEF5350),
  Color(0xFFFF9800),
  Color(0xFFFDD835),
  Color(0xFF66BB6A),
  Color(0xFF26C6DA),
  Color(0xFF42A5F5),
  Color(0xFF7E57C2),
  Color(0xFFEC407A),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const GharApp());
}

class GharApp extends StatelessWidget {
  const GharApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ghar',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF42A5F5),
        ),
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (c, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            return s.data == null ? const LoginPage() : const HomePage();
          },
        ),
      );
}

// ---------------------------------------------------------------- LOGIN

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final nameC = TextEditingController();
  final passC = TextEditingController();
  final codeC = TextEditingController();
  bool busy = false;

  void msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> go(bool register) async {
    final name = nameC.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,16}$').hasMatch(name)) {
      return msg('Naam 3-16 huroof ka ho: a-z, 0-9, _');
    }
    if (passC.text.length < 6) return msg('Password kam az kam 6 huroof');
    if (register && codeC.text.trim() != groupCode) {
      return msg('Group code ghalat hai');
    }
    setState(() => busy = true);
    try {
      final email = '$name@ghar.app';
      if (register) {
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: passC.text);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'name': name,
          'color': palette[Random().nextInt(palette.length)].toARGB32(),
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: passC.text);
      }
    } on FirebaseAuthException catch (e) {
      msg(e.message ?? e.code);
    } catch (e) {
      msg('Masla: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(Icons.home_rounded, size: 80),
                  const Text('Ghar',
                      style:
                          TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameC,
                    decoration: const InputDecoration(
                        labelText: 'Naam (username)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passC,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeC,
                    decoration: const InputDecoration(
                        labelText: 'Group code (sirf naye account ke liye)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  if (busy)
                    const CircularProgressIndicator()
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: () => go(false),
                          child: const Text('Login')),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                          onPressed: () => go(true),
                          child: const Text('Naya account')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------- HOME

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final db = FirebaseFirestore.instance;
  final player = AudioPlayer();
  final queue = <Uint8List>[];
  final names = <String>[];
  final seen = <String>{};
  bool playing = false;
  String? nowPlaying;
  Timer? beat;
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    _beat();
    beat = Timer.periodic(const Duration(seconds: 30), (_) => _beat());

    final start = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(seconds: 10)));
    sub = db
        .collection('clips')
        .where('ts', isGreaterThan: start)
        .orderBy('ts')
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        if (c.doc.metadata.hasPendingWrites) continue;
        if (!seen.add(c.doc.id)) continue;
        final d = c.doc.data();
        if (d == null || d['from'] == uid) continue;
        if (d['to'] != uid && d['to'] != 'all') continue;
        queue.add(base64Decode(d['audio'] as String));
        names.add((d['fromName'] as String?) ?? '?');
      }
      _next();
    });

    player.onPlayerComplete.listen((_) {
      playing = false;
      if (mounted) setState(() => nowPlaying = null);
      _next();
    });
  }

  Future<void> _beat() async {
    try {
      await db.collection('users').doc(uid).set(
          {'lastSeen': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _next() async {
    if (playing || queue.isEmpty) return;
    playing = true;
    final bytes = queue.removeAt(0);
    final who = names.removeAt(0);
    if (mounted) setState(() => nowPlaying = who);
    try {
      await player.play(BytesSource(bytes, mimeType: 'audio/mp4'));
    } catch (_) {
      playing = false;
      if (mounted) setState(() => nowPlaying = null);
    }
  }

  @override
  void dispose() {
    beat?.cancel();
    sub?.cancel();
    player.dispose();
    super.dispose();
  }

  void pickColor() => showModalBottomSheet(
        context: context,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              for (final c in palette)
                GestureDetector(
                  onTap: () {
                    db
                        .collection('users')
                        .doc(uid)
                        .update({'color': c.toARGB32()});
                    Navigator.pop(context);
                  },
                  child: CircleAvatar(radius: 28, backgroundColor: c),
                ),
            ],
          ),
        ),
      );

  Widget tile(String id, Map<String, dynamic> d) {
    final me = id == uid;
    final color = Color((d['color'] as int?) ?? palette[5].toARGB32());
    final ts = d['lastSeen'] as Timestamp?;
    final online = me ||
        (ts != null && DateTime.now().difference(ts.toDate()).inSeconds < 75);
    final name = (d['name'] as String?) ?? '?';
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => me
          ? pickColor()
          : Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      GharPage(uid: id, name: name, color: color))),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.home_rounded,
                      size: 52, color: Colors.black87),
                  const SizedBox(height: 6),
                  Text(me ? 'Mera ghar' : name,
                      style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  if (me)
                    const Text('(rang badlo)',
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: CircleAvatar(
                radius: 6,
                backgroundColor:
                    online ? Colors.greenAccent[700] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Ghar'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  TalkButton(to: 'all', size: 72, color: palette[5]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      nowPlaying != null
                          ? '🔊 $nowPlaying bol raha hai'
                          : 'Sab ko bolo\n(dabaye rakho)',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('users').snapshots(),
                builder: (c, s) {
                  if (!s.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = s.data!.docs.toList()
                    ..sort((a, b) {
                      if (a.id == uid) return -1;
                      if (b.id == uid) return 1;
                      return ((a['name'] ?? '') as String)
                          .compareTo((b['name'] ?? '') as String);
                    });
                  return GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(16),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    children: [for (final d in docs) tile(d.id, d.data())],
                  );
                },
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------- DOST KA GHAR

class GharPage extends StatelessWidget {
  final String uid;
  final String name;
  final Color color;
  const GharPage(
      {super.key, required this.uid, required this.name, required this.color});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: color.withValues(alpha: .22),
        appBar: AppBar(
            title: Text('$name ka ghar'), backgroundColor: Colors.transparent),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home_rounded, size: 120, color: color),
              Text(name,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              TalkButton(to: uid, size: 180, color: color),
              const SizedBox(height: 20),
              const Text('Dabaye rakho aur bolo, chhodo to chali jayegi'),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------- HOLD TO TALK

class TalkButton extends StatefulWidget {
  final String to; // dost ki uid ya 'all'
  final double size;
  final Color color;
  const TalkButton(
      {super.key, required this.to, required this.size, required this.color});
  @override
  State<TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<TalkButton> {
  final rec = AudioRecorder();
  bool on = false;
  bool held = false;
  DateTime? t0;
  Timer? maxT;

  Future<void> _start() async {
    held = true;
    if (!await rec.hasPermission()) {
      held = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mic ki ijazat do')));
      }
      return;
    }
    if (!held) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/c${DateTime.now().millisecondsSinceEpoch}.m4a';
    await rec.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1),
      path: path,
    );
    t0 = DateTime.now();
    on = true;
    if (mounted) setState(() {});
    maxT = Timer(const Duration(seconds: 30), _stop);
    if (!held) await _stop(); // ungli pehle hi utha li thi
  }

  Future<void> _stop() async {
    held = false;
    if (!on) return;
    on = false;
    maxT?.cancel();
    if (mounted) setState(() {});
    final p = await rec.stop();
    if (p == null) return;
    final f = File(p);
    final ms = DateTime.now().difference(t0!).inMilliseconds;
    final bytes = await f.readAsBytes();
    try {
      await f.delete();
    } catch (_) {}
    if (ms < 400 || bytes.length > 700000) return;
    final me = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('clips').add({
      'from': me.uid,
      'fromName': (me.email ?? '').split('@').first,
      'to': widget.to,
      'audio': base64Encode(bytes),
      'ts': FieldValue.serverTimestamp(),
      'expireAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
    });
  }

  @override
  void dispose() {
    maxT?.cancel();
    rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size * (on ? 1.12 : 1.0);
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: SizedBox(
        width: widget.size * 1.12,
        height: widget.size * 1.12,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? Colors.redAccent : widget.color,
              boxShadow: [
                BoxShadow(
                    color: (on ? Colors.redAccent : widget.color)
                        .withValues(alpha: .5),
                    blurRadius: on ? 28 : 12)
              ],
            ),
            child: Icon(on ? Icons.graphic_eq : Icons.mic,
                size: widget.size * .42, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}
