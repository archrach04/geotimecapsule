import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'home_page.dart';
import 'dart:typed_data'; // Make sure this import exists

import 'geo_note.dart';
import 'notes_service.dart';

class NotesListPage extends StatefulWidget {
  final List<GeoNote> notes;
  final LatLng? currentLocation;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onNoteViewed;
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
      _filteredNotes = List<GeoNote>.from(widget.notes);
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
    final decryptedText = NotesService.decryptNote(note);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Note - ${note.mode}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(decryptedText),
              const SizedBox(height: 16),

              // --- MEDIA SECTION ---
              if (note.media != null && note.media!.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Attached Media:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...note.media!.map((m) {
                      final decryptedBytes = Uint8List.fromList(
                          MediaEncryptionHelper.decryptFile(m['data']!, m['iv']!)
                      );
                      // Show image if file extension is image
                      if (m['filename']!.toLowerCase().endsWith('.jpg') ||
                          m['filename']!.toLowerCase().endsWith('.png') ||
                          m['filename']!.toLowerCase().endsWith('.jpeg')) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Image.memory(decryptedBytes, width: 200, height: 200, fit: BoxFit.cover),
                        );
                      } else {
                        // For videos, you can optionally write bytes to a temp file and use video_player
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text('Video: ${m['filename']} (tap to play)'),
                        );
                      }
                    }).toList(),
                  ],
                ),

              Text('Created: ${DateFormat('yyyy-MM-dd HH:mm').format(note.createdAt)}'),
              if (note.location != null)
                Text('Location: ${note.location!.latitude.toStringAsFixed(6)}, ${note.location!.longitude.toStringAsFixed(6)}'),
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
        message +=
        '• The trigger date (${DateFormat('yyyy-MM-dd HH:mm').format(note.triggerDate!)}) has not been reached\n';
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degree) => degree * pi / 180;

  @override
  Widget build(BuildContext context) {
    // Re-filter in case parent passed updated notes
    _filterNotes();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.showAvailableOnly ? 'Available Notes (${_filteredNotes.length})' : 'All Notes (${_filteredNotes.length})'),
      ),
      body: _filteredNotes.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notes, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.showAvailableOnly ? 'No notes available to view' : 'No notes saved yet',
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
            color: isAvailable && !note.hasBeenViewed ? Colors.green[50] : null,
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
              trailing: Icon(isAvailable ? Icons.lock_open : Icons.lock, color: isAvailable ? Colors.green : Colors.grey),
              onTap: () => _viewNote(context, note),
            ),
          );
        },
      ),
    );
  }
}
