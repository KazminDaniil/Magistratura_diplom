import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../services/signaling_service.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _signaling = SignalingService();
  final _roomCodeController = TextEditingController();
  final _uuid = const Uuid();
  late final String _peerId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _peerId = _uuid.v4();
    _signaling.connect(peerId: _peerId);
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _signaling.disconnect();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    try {
      final response = await _signaling.createRoom();
      final roomCode = response['roomCode'];
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(roomCode: roomCode, peerId: _peerId, isCreator: true)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinRoom() async {
    final roomCode = _roomCodeController.text.trim().toUpperCase();
    if (roomCode.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final exists = await _signaling.checkRoomExists(roomCode);
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Комната не найдена')));
        return;
      }
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(roomCode: roomCode, peerId: _peerId, isCreator: false)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Видео-чат'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _isLoading ? null : _createRoom, child: const Text('Создать комнату'))),
              const SizedBox(height: 24),
              TextField(controller: _roomCodeController, enabled: !_isLoading, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'XXXX-XXXX', border: OutlineInputBorder()), maxLength: 8, textCapitalization: TextCapitalization.characters),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _isLoading ? null : _joinRoom, child: const Text('Войти в комнату'))),
              if (_isLoading) const Padding(padding: EdgeInsets.only(top: 24), child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}