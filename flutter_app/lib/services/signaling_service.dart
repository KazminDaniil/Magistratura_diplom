import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class SignalingService {
  //создается 1 уникальный класс
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  static const String serverUrl = 'http://192.168.1.12:3000';
  
  IO.Socket? _socket;
  String? _currentRoomCode;
  String? _peerId;

  //отправляем запрос на сервер на создание комнаты
  Future<Map<String, dynamic>> createRoom() async {
    final response = await http.post(
      Uri.parse('$serverUrl/api/room/create'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to create room');
  }

  Future<bool> checkRoomExists(String roomCode) async {
    final response = await http.get(Uri.parse('$serverUrl/api/room/$roomCode'));
    return response.statusCode == 200;
  }
  //установка соединения с сервером
  void connect({required String peerId}) {
    _peerId = peerId;
    _socket = IO.io(serverUrl, IO.OptionBuilder().setTransports(['websocket']).build());
    _socket?.onConnect((_) => {});
    _socket?.onDisconnect((_) => {});
  }
  //вход в комнату
  void joinRoom(String roomCode) {
    _currentRoomCode = roomCode.toUpperCase();
    _socket?.emit('join_room', {'roomCode': _currentRoomCode, 'peerId': _peerId});
  }
  //обёртки для регистрации обработчика событий
  void onSignal(void Function(Map<String, dynamic>) cb) => _socket?.on('signal', (d) => cb(Map<String, dynamic>.from(d)));
  void onIceCandidate(void Function(Map<String, dynamic>) cb) => _socket?.on('ice_candidate', (d) => cb(Map<String, dynamic>.from(d)));
  void onPeerJoined(void Function(Map<String, dynamic>) cb) => _socket?.on('peer_joined', (d) => cb(Map<String, dynamic>.from(d)));
  void onPeerLeft(void Function(Map<String, dynamic>) cb) => _socket?.on('peer_left', (d) => cb(Map<String, dynamic>.from(d)));
  void onRoomJoined(void Function(Map<String, dynamic>) cb) => _socket?.on('room_joined', (d) => cb(Map<String, dynamic>.from(d)));

  //отправка сигнала
  void sendSignal({required String to, required String from, required Map<String, dynamic> signal, required String type}) {
    _socket?.emit('signal', {'to': to, 'from': from, 'signal': signal, 'type': type});
  }

  //отправка сетевого адреса
  void sendIceCandidate({required String to, required String from, required Map<String, dynamic> candidate}) {
    _socket?.emit('ice_candidate', {'to': to, 'from': from, 'candidate': candidate});
  }

  void leaveRoom() {
    _socket?.emit('disconnecting');
    _currentRoomCode = null;
  }

  void disconnect() {
    leaveRoom();
    _socket?.disconnect();
    _socket = null;
  }

  String? get currentRoomCode => _currentRoomCode;

  void sendChatMessage({required String roomCode, required String from, required String text}) {
    _socket?.emit('chat_message', {
      'roomCode': roomCode,
      'from': from,
      'text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void onChatMessage(void Function(Map<String, dynamic>) callback) {
    _socket?.on('chat_message', (data) => callback(Map<String, dynamic>.from(data)));
  }

}