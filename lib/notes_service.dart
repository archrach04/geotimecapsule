import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'geo_note.dart';
import 'home_page.dart';

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
  static Future<void> saveNoteWithMedia({
    required String content,
    List<File>? mediaFiles,
    LatLng? location,
    required String mode,
    required bool isForSelf,
    DateTime? triggerDate,
  }) async {
    // 1️⃣ Encrypt the text
    final textIv = encrypt.IV.fromSecureRandom(16); // proper random IV
    final textToEncrypt = content.isEmpty ? " " : content;
    final encryptedText = _encrypter.encrypt(textToEncrypt, iv: textIv);

    // 2️⃣ Encrypt media files if any
    List<Map<String, String>>? encryptedMedia;
    if (mediaFiles != null && mediaFiles.isNotEmpty) {
      print('Encrypting text length: ${content.length}');
      print('Media files count: ${mediaFiles.length}');

      encryptedMedia = [];
      for (var file in mediaFiles) {
        final em = await MediaEncryptionHelper.encryptFile(file);
        // encryptFile already generates its own random IV per file
        encryptedMedia.add(em);
      }
    }

    // 3️⃣ Create the GeoNote object
    final note = GeoNote(
      id: _generateId(),
      encryptedContent: encryptedText.base64,
      iv: textIv.base64, // store IV for text
      media: encryptedMedia, // can be null
      location: location,
      createdAt: DateTime.now(),
      mode: mode,
      isForSelf: isForSelf,
      triggerDate: triggerDate,
    );

    // 4️⃣ Save to Hive
    final box = await Hive.openBox<String>(_notesBox);
    await box.put(note.id, jsonEncode(note.toJson()));
  }


  static Future<void> saveNote({
    required String content,
    LatLng? location,
    required String mode,
    required bool isForSelf,
    DateTime? triggerDate,



  }) async {
    final iv = encrypt.IV.fromSecureRandom(16); // 16 bytes random

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
    return box.values.map((e) => GeoNote.fromJson(jsonDecode(e))).toList();
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

  static bool isNoteTriggered(GeoNote note, LatLng? currentLocation) {
    if (note.mode.contains('Date') && note.triggerDate != null) {
      if (DateTime.now().isBefore(note.triggerDate!)) return false;
    }

    if (note.mode.contains('Geofence') && note.location != null && currentLocation != null) {
      final distance = _calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        note.location!.latitude,
        note.location!.longitude,
      );
      if (distance > 100) return false;
    }

    return true;
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degree) => degree * pi / 180;
}
