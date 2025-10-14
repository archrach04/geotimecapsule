// home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'main.dart';
import 'notes_service.dart';
import 'geo_note.dart';
import 'notes_list_page.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class MediaEncryptionHelper {
  static final _key = encrypt.Key.fromUtf8('my32lengthsupersecretkey!!123456');
  static final _encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));

  static Future<Map<String, String>> encryptFile(File file) async {
    final bytes = await file.readAsBytes();
    final iv = encrypt.IV.fromSecureRandom(16); // correct IV generation
    final encrypted = _encrypter.encryptBytes(bytes, iv: iv);

    return {
      'filename': file.path.split('/').last,
      'data': encrypted.base64,
      'iv': iv.base64,
    };
  }

  static Uint8List decryptFile(String base64Data, String base64Iv) {
    final encrypted = encrypt.Encrypted.fromBase64(base64Data);
    final iv = encrypt.IV.fromBase64(base64Iv);
    final decryptedBytes = _encrypter.decryptBytes(encrypted, iv: iv);
    return Uint8List.fromList(decryptedBytes); // <-- convert to Uint8List
  }

}
class MediaHelper {
  static final ImagePicker _picker = ImagePicker();

  // Pick image from gallery
  static Future<File?> pickImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    return file != null ? File(file.path) : null;
  }

  // Pick video from gallery
  static Future<File?> pickVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.gallery);
    return file != null ? File(file.path) : null;
  }

  // Take photo from camera
  static Future<File?> takePhoto() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.camera);
    return file != null ? File(file.path) : null;
  }

  // Record video from camera
  static Future<File?> recordVideo() async {
    final XFile? file = await _picker.pickVideo(source: ImageSource.camera);
    return file != null ? File(file.path) : null;
  }
}



class PermissionsHelper {
  static Future<bool> requestStorageAndCamera() async {
    final statuses = await [
      Permission.camera,
      Permission.photos,       // iOS
      Permission.storage,      // Android
      Permission.videos,       // optional
    ].request();

    return statuses.values.any((status) => status.isGranted);
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
  Timer? _periodicTimer;

  Future<void> _pickAndSaveMedia() async {
    // 1️⃣ Request permissions
    final granted = await PermissionsHelper.requestStorageAndCamera();
    if (!granted) {
      _showSnackBar('Storage or camera permission denied', isError: true);
      return;
    }

    // 2️⃣ Pick multiple media files (images/videos)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'gif', // images
        'mp4', 'mov', 'avi',          // videos
      ],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) {
      _showSnackBar('No files selected', isError: true);
      return;
    }

    // 3️⃣ Convert to File objects
    final mediaFiles = result.paths.map((path) => File(path!)).toList();

    // 4️⃣ Save note with media (encrypted)
    try {
      await NotesService.saveNoteWithMedia(
        content: _noteController.text.trim(),
        mediaFiles: mediaFiles,
        location: _currentLocation,
        mode: _selectedMode,
        isForSelf: _notesForSelf,
        triggerDate: _selectedTriggerDate,
      );

      _noteController.clear();
      if (mounted) setState(() => _selectedTriggerDate = null);
      await _loadNotes();
      _showSnackBar('Note with media saved securely');
    } catch (e) {
      _showSnackBar('Failed to save note: $e', isError: true);
    }
  }




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
    _periodicTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicChecks() {
    // cancel existing timer if any
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) return;
      _checkForAvailableNotes();
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
        // Center the map on the current location (only if mapController is ready)
        try {
          _mapController.move(_currentLocation!, 15.0);
        } catch (_) {}
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
  Set<String> _notifiedNotes = {};

  void _checkForAvailableNotes() {
    if (_currentLocation == null) return;

    final availableNotes = _savedNotes.where((note) {
      return NotesService.isNoteTriggered(note, _currentLocation) &&
          !note.hasBeenViewed &&
          !_notifiedNotes.contains(note.id);
    }).toList();

    if (mounted) setState(() => _availableNotes = availableNotes);

    for (var note in availableNotes) {
      _showNotification(note);
      _notifiedNotes.add(note.id); // mark as notified
    }
  }

  Future<void> _showNotification(GeoNote note) async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
        'notes_channel', 'Notes Notifications',
        channelDescription: 'Notifications for available notes',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker');

    const NotificationDetails platformDetails =
    NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
        int.parse(note.id.hashCode.toString().substring(0, 7)), // unique id
        'Note Available',
        'Your note "${note.id.substring(note.id.length - 4)}" is now available!',
        platformDetails,
        payload: note.id);
  }

  void _showAvailableNotesNotification(List<GeoNote> notes) {
    // If a dialog is already open, skip
    if (!mounted) return;
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
      if (mounted) _showSnackBar('Please enter a note', isError: true);
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
      if (mounted) setState(() => _selectedTriggerDate = null);
      await _loadNotes();
      if (mounted) _showSnackBar('Note saved securely');
    } catch (e) {
      if (mounted) _showSnackBar('Failed to save note: $e', isError: true);
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
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedTriggerDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
                icon: const Icon(Icons.notes),
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
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text(
                      _availableNotes.length.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 8),
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
                      width: 40,
                      height: 40,
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
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _selectedMode = val;
                        // if switched off date, clear selected trigger
                        if (!_selectedMode.contains('Date')) {
                          _selectedTriggerDate = null;
                        }
                      });
                    },
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

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _pickAndSaveMedia,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Attach Images/Videos'),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    ),
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
