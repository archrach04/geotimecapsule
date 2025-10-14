import 'package:latlong2/latlong.dart';

class GeoNote {
  final String id;
  final String encryptedContent; // text content
  final String iv;
  final LatLng? location;
  final DateTime createdAt;
  final String mode;
  final bool isForSelf;
  final DateTime? triggerDate;
  final bool hasBeenViewed;
  final List<Map<String, String>>? media;

  GeoNote({
    required this.id,
    required this.encryptedContent,
    required this.iv,
    this.location,
    required this.createdAt,
    required this.mode,
    required this.isForSelf,
    this.triggerDate,
    this.media,
    this.hasBeenViewed = false,

  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'encryptedContent': encryptedContent,
    'iv': iv,
    'media': media,
    'location': location != null ? {'lat': location!.latitude, 'lng': location!.longitude} : null,
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
    media: json['media'] != null
        ? List<Map<String, String>>.from(
      json['media'].map((m) => Map<String, String>.from(m)),
    )
        : null,
    location: json['location'] != null ? LatLng(json['location']['lat'], json['location']['lng']) : null,
    createdAt: DateTime.parse(json['createdAt']),
    mode: json['mode'],
    isForSelf: json['isForSelf'],
    triggerDate: json['triggerDate'] != null ? DateTime.parse(json['triggerDate']) : null,
    hasBeenViewed: json['hasBeenViewed'] ?? false,
  );
}
