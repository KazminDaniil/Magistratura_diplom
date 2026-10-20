class RoomModel {
  final String code;
  final String id;
  final DateTime createdAt;
  final List<String> peers;

  RoomModel({
    required this.code,
    required this.id,
    required this.createdAt,
    this.peers = const [],
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      code: json['roomCode'] ?? json['code'],
      id: json['roomId'] ?? json['id'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      peers: List<String>.from(json['peers'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'peers': peers,
    };
  }
}