import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'TON_URL_SUPABASE';
const supabaseAnonKey = 'TA_CLE_PUBLIABLE_SUPABASE';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.startsWith('http') &&
      supabaseAnonKey != 'TA_CLE_PUBLIABLE_SUPABASE') {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  runApp(const WinnersApp());
}

class WinnersApp extends StatelessWidget {
  const WinnersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Winners to School',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class SchoolRecord {
  String id;
  String year;
  String trimester;
  String sequence;
  List<Map<String, dynamic>> subjects;

  SchoolRecord({
    required this.id,
    required this.year,
    required this.trimester,
    required this.sequence,
    required this.subjects,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'year': year,
        'trimester': trimester,
        'sequence': sequence,
        'subjects': subjects,
      };

  factory SchoolRecord.fromJson(Map<String, dynamic> json) {
    return SchoolRecord(
      id: json['id'] ?? '',
      year: json['year'] ?? '',
      trimester: json['trimester'] ?? 'Trimestre 1',
      sequence: json['sequence'] ?? 'Séquence 1',
      subjects: List<Map<String, dynamic>>.from(
        (json['subjects'] ?? []).map(
          (e) => Map<String, dynamic>.from(e),
        ),
      ),
    );
  }

  double get average {
    double total = 0;
    double coefficients = 0;

    for (final s in subjects) {
      final grade = (s['grade'] as num?)?.toDouble() ?? 0;
      final coefficient = (s['coefficient'] as num?)?.toDouble() ?? 1;

      if (grade >= 0 && grade <= 20 && coefficient > 0) {
        total += grade * coefficient;
        coefficients += coefficient;
      }
    }

    return coefficients == 0 ? 0 : total / coefficients;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<SchoolRecord> records = [];
  bool localMode = false;
  bool english = false;
  bool loading = true;
  String role = 'Élève';
  String studentName = '';
  int page = 0;

  bool get cloudConfigured =>
      supabaseUrl.startsWith('http') &&
      supabaseAnonKey != 'TA_CLE_PUBLIABLE_SUPABASE';

  SupabaseClient? get db =>
      cloudConfigured ? Supabase.instance.client : null;

  String tr(String fr, String en) => english ? en : fr;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    localMode = prefs.getBool('localMode') ?? false;
    role = prefs.getString('role') ?? 'Élève';
    studentName = prefs.getString('studentName') ?? '';

    if (!localMode && db?.auth.currentUser != null) {
      await _loadCloud();
    } else {
      final saved = prefs.getString('schoolRecords');
      if (saved != null) {
        records
          ..clear()
          ..addAll(
            (jsonDecode(saved) as List)
                .map((e) => SchoolRecord.fromJson(
                    Map<String, dynamic>.from(e))),
          );
      }
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'schoolRecords',
      jsonEncode(records.map((e) => e.toJson()).toList()),
    );

    await prefs.setBool('localMode', localMode);
    await prefs.setString('role', role);
    await prefs.setString('studentName', studentName);

    if (!localMode && db?.auth.currentUser != null) {
      await _saveCloud();
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadCloud() async {
    try {
      final user = db!.auth.currentUser!;
      final result = await db!
          .from('student_data')
          .select('data')
          .eq('user_id', user.id)
          .maybeSingle();

      if (result != null) {
        final data = Map<String, dynamic>.from(result['data']);
        records
          ..clear()
          ..addAll(
            (data['records'] as List? ?? []).map(
              (e) => SchoolRecord.fromJson(
                Map<String, dynamic>.from(e),
              ),
            ),
          );
        role = data['role'] ?? role;
        studentName = data['studentName'] ?? studentName;
      }
    } catch (e) {
      _message('Impossible de charger les données en ligne.');
    }
  }

  Future<void> _saveCloud() async {
    try {
      final user = db!.auth.currentUser!;

      await db!.from('student_data').upsert({
        'user_id': user.id,
        'data': {
          'role': role,
          'studentName': studentName,
          'records': records.map((e) => e.toJson()).toList(),
        },
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      _message('Échec de la sauvegarde en ligne. Vérifie Supabase.');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _login() async {
    if (db == null) {
      _message('Configure d’abord Supabase dans le code.');
      return;
    }

    final phone = TextEditingController();
    final otp = TextEditingController();
    bool codeSent = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(codeSent
              ? 'Vérifier le code SMS'
              : 'Connexion par téléphone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone avec indicatif (+237...)',
                ),
              ),
              if (codeSent)
                TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Code reçu par SMS',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  if (!codeSent) {
                    await db!.auth.signInWithOtp(
                      phone: phone.text.trim(),
                    );
                    setDialogState(() => codeSent = true);
                  } else {
                    await db!.auth.verifyOTP(
                      phone: phone.text.trim(),
                      token: otp.text.trim(),
                      type: OtpType.sms,
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }

                    await _loadData();
                    if (mounted) setState(() {});
                  }
                } catch (e) {
                  _message('Connexion impossible : vérifie le numéro et la configuration SMS.');
                }
              },
              child: Text(codeSent ? 'Vérifier' : 'Envoyer le code'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseProfile() async {
    String selectedRole = role;
    final name = TextEditingController(text: studentName);

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Créer mon profil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Nom ou prénom',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Je suis',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Élève',
                    child: Text('Élève'),
                  ),
                  DropdownMenuItem(
                    value: 'Étudiant',
                    child: Text('Étudiant'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedRole = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                role = selectedRole;
                studentName = name.text.trim();
                await _saveData();
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRecord() async {
    final year = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final sequence = TextEditingController(text: 'Séquence 1');
    String trimester = 'Trimestre 1';

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle séquence'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: year,
                  decoration: const InputDecoration(
                    labelText: 'Année scolaire',
                    hintText: '2026-2027',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: trimester,
                  decoration: const InputDecoration(
                    labelText: 'Trimestre',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Trimestre 1',
                      child: Text('Trimestre 1'),
                    ),
                    DropdownMenuItem(
                      value: 'Trimestre 2',
                      child: Text('Trimestre 2'),
                    ),
                    DropdownMenuItem(
                      value: 'Trimestre 3',
                      child: Text('Trimestre 3'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => trimester = v);
                    }
                  },
                ),
                TextField(
                  controller: sequence,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la séquence',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                records.add(
                  SchoolRecord(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    year: year.text.trim(),
                    trimester: trimester,
                    sequence: sequence.text.trim(),
                    subjects: [],
                  ),
                );
                await _saveData();
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRecord(SchoolRecord record) async {
    final subject = TextEditingController();
    final grade = TextEditingController();
    final coefficient = TextEditingController(text: '1');

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajouter une matière'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subject,
                decoration: const InputDecoration(
                  labelText: 'Matière',
                ),
              ),
              TextField(
                controller: grade,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Note sur 20',
                ),
              ),
              TextField(
                controller: coefficient,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Coefficient',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final g = double.tryParse(grade.text.replaceAll(',', '.'));
              final c = double.tryParse(
                  coefficient.text.replaceAll(',', '.'));

              if (subject.text.trim().isEmpty ||
                  g == null ||
                  g < 0 ||
                  g > 20 ||
                  c == null ||
                  c <= 0) {
                _message('Entre une matière, une note de 0 à 20 et un coefficient positif.');
                return;
              }

              record.subjects.add({
                'name': subject.text.trim(),
                'grade': g,
                'coefficient': c,
              });

              await _saveData();
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecord(SchoolRecord record) async {
    records.removeWhere((e) => e.id == record.id);
    await _saveData();
  }

  Widget _recordCard(SchoolRecord record) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${record.year} • ${record.trimester}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(record.sequence),
            const SizedBox(height: 8),
            Text(
              'Moyenne : ${record.average.toStringAsFixed(2)}/20',
              style: TextStyle(
                fontSize: 20,
                color: record.average < 10 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            if (record.subjects.isEmpty)
              const Text('Aucune matière ajoutée.')
            else
              ...record.subjects.map((s) {
                final grade = (s['grade'] as num).toDouble();
                final coeff = (s['coefficient'] as num).toDouble();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['name']),
                  subtitle: Text('Coefficient : $coeff'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${grade.toStringAsFixed(2)}/20',
                        style: TextStyle(
                          color: grade < 10 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          record.subjects.remove(s);
                          await _saveData();
                        },
                      ),
                    ],
                  ),
                );
              }),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _editRecord(record),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une matière'),
                ),
                TextButton.icon(
                  onPressed: () => _deleteRecord(record),
                  icon: const Icon(Icons.delete),
                  label: const Text('Supprimer la séquence'),
                ),
              ],
            ),
            if (record.subjects.any(
                (s) => (s['grade'] as num).toDouble() < 10))
              const Text(
                'Des matières nécessitent des révisions.',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }

  Widget _homeTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('Bienvenue sur Winners to School',
              'Welcome to Winners to School'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(studentName.isEmpty ? role : '$studentName • $role'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mon espace scolaire',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Séquences enregistrées : ${records.length}'),
                Text(
                  'Moyenne générale des séquences : '
                  '${records.isEmpty ? '0.00' : (records.map((e) => e.average).reduce((a, b) => a + b) / records.length).toStringAsFixed(2)}/20',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _addRecord,
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle séquence'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...records.map(_recordCard),
      ],
    );
  }

  Widget _tutorTab() {
    final weak = records
        .expand((r) => r.subjects.map((s) => {
              ...s,
              'year': r.year,
              'sequence': r.sequence,
            }))
        .where((s) => (s['grade'] as num).toDouble() < 10)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('Mon aide scolaire', 'My study assistant'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Voici les matières dans lesquelles tu peux renforcer tes connaissances :',
        ),
        if (weak.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Aucune note inférieure à 10/20 enregistrée pour le moment.',
              ),
            ),
          ),
        ...weak.map(
          (s) => Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: Text(s['name']),
              subtitle: Text(
                'Note : ${s['grade']}/20 • ${s['sequence']}',
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => _openLesson(s['name']),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'La génération automatique de cours détaillés, de résumés et de corrections nécessite de connecter un service IA sécurisé au serveur.',
        ),
      ],
    );
  }

  Future<void> _openLesson(String subject) async {
    final topic = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Réviser : $subject'),
        content: TextField(
          controller: topic,
          decoration: const InputDecoration(
            labelText: 'Chapitre que tu ne comprends pas',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _message(
                'Chapitre enregistré dans ta demande. Le service IA doit encore être connecté au serveur.',
              );
            },
            child: const Text('Demander de l’aide'),
          ),
        ],
      ),
    );
  }

  Widget _profileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('Mon compte', 'My account'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        ListTile(
          leading: const Icon(Icons.person),
          title: Text(studentName.isEmpty ? 'Mon profil' : studentName),
          subtitle: Text(role),
          trailing: const Icon(Icons.edit),
          onTap: _chooseProfile,
        ),
        SwitchListTile(
          title: const Text('Enregistrer sur ce téléphone'),
          subtitle: Text(
            localMode
                ? 'Stockage local activé'
                : 'Sauvegarde dans le compte en ligne si connecté',
          ),
          value: localMode,
          onChanged: (value) async {
            setState(() => localMode = value);
            await _saveData();
          },
        ),
        SwitchListTile(
          title: const Text('English / Français'),
          value: english,
          onChanged: (value) => setState(() => english = value),
        ),
        ListTile(
          leading: const Icon(Icons.cloud),
          title: const Text('Compte en ligne'),
          subtitle: Text(
            db?.auth.currentUser?.phone ??
                'Non connecté : configure Supabase et connecte-toi.',
          ),
          trailing: FilledButton(
            onPressed: _login,
            child: const Text('Connexion'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.save),
          title: const Text('Sauvegarder maintenant'),
          onTap: _saveData,
        ),
        if (db?.auth.currentUser != null)
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () async {
              await db!.auth.signOut();
              if (mounted) setState(() {});
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = [
      _homeTab(),
      _tutorTab(),
      _profileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Winners to School'),
        actions: [
          IconButton(
            tooltip: 'Créer un profil',
            onPressed: _chooseProfile,
            icon: const Icon(Icons.account_circle),
          ),
        ],
      ),
      body: tabs[page],
      floatingActionButton: page == 0
          ? FloatingActionButton(
              onPressed: _addRecord,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (i) => setState(() => page = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.school),
            label: 'École',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book),
            label: 'Révisions',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
