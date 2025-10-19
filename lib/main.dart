import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:math';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isAuthenticating = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    setState(() { _isAuthenticating = true; });
    try {
      bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to access Secure Geo Notes',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (didAuthenticate && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SecureGeoNotesApp()),
        );
      } else {
        setState(() { _error = 'Authentication failed.'; });
      }
    } on PlatformException catch (e) {
      setState(() { _error = e.message ?? 'Error'; });
    }
    setState(() { _isAuthenticating = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _isAuthenticating
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 220,
                    child: Image.asset('assets/tess.gif'),
                  ),
                  const SizedBox(height: 24),
                  const Text('Authenticating...'),
                ],
              )
            : _error.isNotEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_error),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _authenticate,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 220,
                        child: Image.asset('assets/tess.gif'),
                      ),
                      const SizedBox(height: 24),
                      const Text('Loading...'),
                    ],
                  ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const MaterialApp(
    home: LoadingPage(),
    debugShowCheckedModeBanner: false,
  ));
}

class SecureGeoNotesApp extends StatelessWidget {
  const SecureGeoNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Geo Notes',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF0099),
          brightness: Brightness.light,
          primary: const Color(0xFFFF0099),
          secondary: const Color(0xFFFF0099),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF0099),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF0099),
            foregroundColor: Colors.white,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFF0099),
          foregroundColor: Colors.white,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(const Color(0xFFFF0099)),
          trackColor: WidgetStateProperty.all(const Color(0xFFFFB3E6)),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFFF0099)),
          ),
          border: OutlineInputBorder(),
        ),
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
  final bool hasBeenViewed;

  GeoNote({
    required this.id,
    required this.encryptedContent,
    required this.iv,
    this.location,
    required this.createdAt,
    required this.mode,
    required this.isForSelf,
    this.triggerDate,
    this.hasBeenViewed = false,
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
        'hasBeenViewed': hasBeenViewed,
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
        hasBeenViewed: json['hasBeenViewed'] ?? false,
      );
}

class NotesService {
  static const String _notesBox = 'geo_notes';
  static const String _keyString = 'my32lengthsupersecretkey!!123456';

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

  static Future<void> markNoteAsViewed(String id) async {
    final box = await Hive.openBox<String>(_notesBox);
    final noteJson = box.get(id);
    if (noteJson != null) {
      final noteMap = jsonDecode(noteJson);
      noteMap['hasBeenViewed'] = true;
      await box.put(id, jsonEncode(noteMap));
    }
  }

  // Check if a note's trigger conditions are met
  static bool isNoteTriggered(GeoNote note, LatLng? currentLocation) {
    // Check date trigger
    if (note.mode.contains('Date') && note.triggerDate != null) {
      if (DateTime.now().isBefore(note.triggerDate!)) {
        return false;
      }
    }

    // Check location trigger
    if (note.mode.contains('Geofence') && note.location != null && currentLocation != null) {
      final distance = _calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        note.location!.latitude,
        note.location!.longitude,
      );
      
      // If we're not within 100 meters of the target location
      if (distance > 100) { // 100 meters threshold
        return false;
      }
    }

    return true;
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180;
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
  List<GeoNote> _availableNotes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
    _startPeriodicChecks();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForAvailableNotes();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteController.dispose();
    super.dispose();
  }

  void _startPeriodicChecks() {
    // Check for available notes every 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _checkForAvailableNotes();
        _startPeriodicChecks();
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      await _getCurrentLocation();
      await _loadNotes();
      _checkForAvailableNotes();
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

  void _checkForAvailableNotes() {
    if (_currentLocation == null) return;

    final availableNotes = _savedNotes.where((note) {
      return NotesService.isNoteTriggered(note, _currentLocation) && !note.hasBeenViewed;
    }).toList();

    if (mounted) {
      setState(() {
        _availableNotes = availableNotes;
      });
    }

    // Show notification if there are new available notes
    if (availableNotes.isNotEmpty && mounted) {
      _showAvailableNotesNotification(availableNotes);
    }
  }

  void _showAvailableNotesNotification(List<GeoNote> notes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('New Notes Available!'),
          content: Text('You have ${notes.length} note(s) that can now be viewed.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _viewNotes(showAvailableOnly: true);
              },
              child: const Text('View Notes'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Dismiss'),
            ),
          ],
        );
      },
    );
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

  void _viewNotes({bool showAvailableOnly = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotesListPage(
          notes: _savedNotes,
          currentLocation: _currentLocation,
          onDelete: (id) async {
            await NotesService.deleteNote(id);
            await _loadNotes();
            _checkForAvailableNotes();
          },
          onNoteViewed: (id) async {
            await NotesService.markNoteAsViewed(id);
            await _loadNotes();
            _checkForAvailableNotes();
          },
          showAvailableOnly: showAvailableOnly,
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
          Stack(
            children: [
              IconButton(
                onPressed: _viewNotes, 
                icon: const Icon(Icons.notes)
              ),
              if (_availableNotes.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      _availableNotes.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
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
                    initialValue: _selectedMode,
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

class NotesListPage extends StatefulWidget {
  final List<GeoNote> notes;
  final LatLng? currentLocation;
  final Function(String) onDelete;
  final Function(String) onNoteViewed;
  final bool showAvailableOnly;

  const NotesListPage({
    super.key,
    required this.notes,
    this.currentLocation,
    required this.onDelete,
    required this.onNoteViewed,
    this.showAvailableOnly = false,
  });

  @override
  State<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  late List<GeoNote> _filteredNotes;

  @override
  void initState() {
    super.initState();
    _filterNotes();
  }

  void _filterNotes() {
    if (widget.showAvailableOnly) {
      _filteredNotes = widget.notes.where((note) {
        return NotesService.isNoteTriggered(note, widget.currentLocation) && !note.hasBeenViewed;
      }).toList();
    } else {
      _filteredNotes = widget.notes;
    }
  }

  void _viewNote(BuildContext context, GeoNote note) {
    // Check if note can be viewed
    if (!NotesService.isNoteTriggered(note, widget.currentLocation)) {
      _showCannotViewDialog(note);
      return;
    }

    // Mark as viewed and show content
    widget.onNoteViewed(note.id);
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
              if (note.hasBeenViewed)
                const Text('Status: Viewed', style: TextStyle(color: Colors.green)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await widget.onDelete(note.id);
              setState(() {
                _filterNotes();
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCannotViewDialog(GeoNote note) {
    String message = 'This note cannot be viewed yet because:\n\n';
    
    if (note.mode.contains('Date') && note.triggerDate != null) {
      if (DateTime.now().isBefore(note.triggerDate!)) {
        message += '• The trigger date (${DateFormat('yyyy-MM-dd HH:mm').format(note.triggerDate!)}) has not been reached\n';
      }
    }

    if (note.mode.contains('Geofence') && note.location != null) {
      if (widget.currentLocation == null) {
        message += '• Your current location is unavailable\n';
      } else {
        final distance = NotesService.isNoteTriggered(note, widget.currentLocation) 
            ? 0 
            : _calculateDistance(
                widget.currentLocation!.latitude,
                widget.currentLocation!.longitude,
                note.location!.latitude,
                note.location!.longitude,
              );
        message += '• You are ${distance.toStringAsFixed(0)} meters away from the target location\n';
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Note Not Available'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.showAvailableOnly 
            ? 'Available Notes (${_filteredNotes.length})'
            : 'All Notes (${_filteredNotes.length})'),
      ),
      body: _filteredNotes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notes, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    widget.showAvailableOnly 
                        ? 'No notes available to view'
                        : 'No notes saved yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _filteredNotes.length,
              itemBuilder: (context, index) {
                final note = _filteredNotes[index];
                final isAvailable = NotesService.isNoteTriggered(note, widget.currentLocation);
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  color: isAvailable && !note.hasBeenViewed 
                      ? Colors.green[50]
                      : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isAvailable
                          ? (note.hasBeenViewed ? Colors.blue : Colors.green)
                          : Colors.grey,
                      child: Icon(
                        note.isForSelf ? Icons.person : Icons.share,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    title: Text('Note ${note.id.substring(note.id.length - 4)}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mode: ${note.mode}'),
                        Text('Created: ${DateFormat('yyyy-MM-dd HH:mm').format(note.createdAt)}'),
                        if (note.triggerDate != null)
                          Text('Triggers: ${DateFormat('yyyy-MM-dd HH:mm').format(note.triggerDate!)}'),
                        if (!isAvailable)
                          const Text('Status: Not available', style: TextStyle(color: Colors.red)),
                        if (isAvailable && note.hasBeenViewed)
                          const Text('Status: Viewed', style: TextStyle(color: Colors.blue)),
                        if (isAvailable && !note.hasBeenViewed)
                          const Text('Status: Available now!', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                    trailing: Icon(
                      isAvailable ? Icons.lock_open : Icons.lock,
                      color: isAvailable ? Colors.green : Colors.grey,
                    ),
                    onTap: () => _viewNote(context, note),
                  ),
                );
              },
            ),
    );
  }
}
