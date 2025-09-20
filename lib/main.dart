import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const SecureGeoNotesApp());
}

class SecureGeoNotesApp extends StatelessWidget {
  const SecureGeoNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Geo Notes',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GeoNote {
  final String id;
  final String encryptedContent;
  final String iv;
  final LatLng? location;
  final DateTime createdAt;
  final String mode;
  final bool isForSelf;
  final DateTime? triggerDate;

  GeoNote({
    required this.id,
    required this.encryptedContent,
    required this.iv,
    this.location,
    required this.createdAt,
    required this.mode,
    required this.isForSelf,
    this.triggerDate,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'encryptedContent': encryptedContent,
        'iv': iv,
        'location': location != null
            ? {'lat': location!.latitude, 'lng': location!.longitude}
            : null,
        'createdAt': createdAt.toIso8601String(),
        'mode': mode,
        'isForSelf': isForSelf,
        'triggerDate': triggerDate?.toIso8601String(),
      };

  factory GeoNote.fromJson(Map<String, dynamic> json) => GeoNote(
        id: json['id'],
        encryptedContent: json['encryptedContent'],
        iv: json['iv'],
        location: json['location'] != null
            ? LatLng(json['location']['lat'], json['location']['lng'])
            : null,
        createdAt: DateTime.parse(json['createdAt']),
        mode: json['mode'],
        isForSelf: json['isForSelf'],
        triggerDate:
            json['triggerDate'] != null ? DateTime.parse(json['triggerDate']) : null,
      );
}

class NotesService {
  static const String _notesBox = 'geo_notes';
  static const String _keyString = 'my32lengthsupersecretkey!!!123456';

  static final encrypt.Key _aesKey = encrypt.Key.fromUtf8(_keyString);
  static final encrypt.Encrypter _encrypter = encrypt.Encrypter(encrypt.AES(_aesKey));

  static String _generateId() {
    final random = Random();
    return DateTime.now().millisecondsSinceEpoch.toString() +
        random.nextInt(1000).toString();
  }

  static Future<void> saveNote({
    required String content,
    LatLng? location,
    required String mode,
    required bool isForSelf,
    DateTime? triggerDate,
  }) async {
    final iv = encrypt.IV.fromLength(16);
    final encrypted = _encrypter.encrypt(content, iv: iv);

    final note = GeoNote(
      id: _generateId(),
      encryptedContent: encrypted.base64,
      iv: iv.base64,
      location: location,
      createdAt: DateTime.now(),
      mode: mode,
      isForSelf: isForSelf,
      triggerDate: triggerDate,
    );

    final box = await Hive.openBox<String>(_notesBox);
    await box.put(note.id, jsonEncode(note.toJson()));
  }

  static Future<List<GeoNote>> loadNotes() async {
    final box = await Hive.openBox<String>(_notesBox);
    return box.values
        .map((e) => GeoNote.fromJson(jsonDecode(e)))
        .toList();
  }

  static String decryptNote(GeoNote note) {
    final iv = encrypt.IV.fromBase64(note.iv);
    final encrypted = encrypt.Encrypted.fromBase64(note.encryptedContent);
    return _encrypter.decrypt(encrypted, iv: iv);
  }

  static Future<void> deleteNote(String id) async {
    final box = await Hive.openBox<String>(_notesBox);
    await box.delete(id);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController _noteController = TextEditingController();
  LatLng? _currentLocation;
  bool _notesForSelf = true;
  String _selectedMode = 'Geofence + Date';
  List<GeoNote> _savedNotes = [];
  bool _isLoading = true;
  String _errorMessage = '';
  DateTime? _selectedTriggerDate;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      await _getCurrentLocation();
      await _loadNotes();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        // Center the map on the current location
        _mapController.move(_currentLocation!, 15.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Location error: $e';
        });
      }
    }
  }

  Future<void> _loadNotes() async {
    try {
      final notes = await NotesService.loadNotes();
      if (mounted) {
        setState(() => _savedNotes = notes);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to load notes: $e', isError: true);
      }
    }
  }

  Future<void> _saveNote() async {
    if (_noteController.text.trim().isEmpty) {
      if (mounted) {
        _showSnackBar('Please enter a note', isError: true);
      }
      return;
    }

    LatLng? noteLocation;
    if (_selectedMode.contains('Geofence') && _currentLocation != null) {
      noteLocation = _currentLocation;
    }

    try {
      await NotesService.saveNote(
        content: _noteController.text.trim(),
        location: noteLocation,
        mode: _selectedMode,
        isForSelf: _notesForSelf,
        triggerDate: _selectedTriggerDate,
      );

      _noteController.clear();
      if (mounted) {
        setState(() => _selectedTriggerDate = null);
      }
      await _loadNotes();
      if (mounted) {
        _showSnackBar('Note saved securely');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to save note: $e', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Future<void> _selectTriggerDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedTriggerDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && mounted) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (time != null && mounted) {
        setState(() {
          _selectedTriggerDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  void _viewNotes() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotesListPage(
          notes: _savedNotes,
          onDelete: (id) async {
            await NotesService.deleteNote(id);
            await _loadNotes();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_errorMessage.isNotEmpty && _currentLocation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Secure Geo Notes')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(_errorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _initializeApp, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Geo Notes'),
        actions: [
          IconButton(
            onPressed: _viewNotes, 
            icon: const Icon(Icons.notes)
          ),
          IconButton(
            onPressed: _getCurrentLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: _currentLocation != null
                ? FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      center: _currentLocation!,
                      zoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.secure_geo_notes',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentLocation!,
                            builder: (ctx) => const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Notes for Self'),
                    subtitle: Text(_notesForSelf ? 'Private notes' : 'Shared notes'),
                    value: _notesForSelf,
                    onChanged: (val) => setState(() => _notesForSelf = val),
                  ),
                  DropdownButtonFormField<String>(
                    value: _selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Trigger Mode',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Date', child: Text('Date Only')),
                      DropdownMenuItem(value: 'Geofence', child: Text('Location Only')),
                      DropdownMenuItem(value: 'Geofence + Date', child: Text('Location + Date')),
                    ],
                    onChanged: (val) => setState(() => _selectedMode = val!),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedMode.contains('Date'))
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(_selectedTriggerDate != null
                          ? 'Trigger: ${DateFormat('yyyy-MM-dd HH:mm').format(_selectedTriggerDate!)}'
                          : 'Select trigger date/time'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: _selectTriggerDate,
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Enter your note',
                      hintText: 'Type your secure note here...',
                    ),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveNote,
                      icon: const Icon(Icons.security),
                      label: const Text('Save Secure Note'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NotesListPage extends StatelessWidget {
  final List<GeoNote> notes;
  final Function(String) onDelete;

  const NotesListPage({super.key, required this.notes, required this.onDelete});

  void _viewNote(BuildContext context, GeoNote note) {
    final decrypted = NotesService.decryptNote(note);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Note - ${note.mode}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(decrypted),
              const SizedBox(height: 16),
              Text('Created: ${DateFormat('yyyy-MM-dd HH:mm').format(note.createdAt)}'),
              if (note.location != null)
                Text(
                    'Location: ${note.location!.latitude.toStringAsFixed(6)}, ${note.location!.longitude.toStringAsFixed(6)}'),
              if (note.triggerDate != null)
                Text('Trigger: ${DateFormat('yyyy-MM-dd HH:mm').format(note.triggerDate!)}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await onDelete(note.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Saved Notes (${notes.length})')),
      body: notes.isEmpty
          ? const Center(child: Text('No notes saved yet'))
          : ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(note.isForSelf ? Icons.person : Icons.share, size: 20),
                    ),
                    title: Text('Note ${note.id.substring(note.id.length - 4)}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mode: ${note.mode}'),
                        Text('Created: ${DateFormat('yyyy-MM-dd HH:mm').format(note.createdAt)}'),
                        if (note.triggerDate != null)
                          Text('Triggers: ${DateFormat('yyyy-MM-dd HH:mm').format(note.triggerDate!)}'),
                      ],
                    ),
                    trailing: const Icon(Icons.lock),
                    onTap: () => _viewNote(context, note),
                  ),
                );
              },
            ),
    );
  }
}