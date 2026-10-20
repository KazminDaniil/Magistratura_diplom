import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import '../services/signaling_service.dart';

class CallScreen extends StatefulWidget {
  final String roomCode;
  final String peerId;
  final bool isCreator;
  const CallScreen({super.key, required this.roomCode, required this.peerId, required this.isCreator});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class ChatMessage {
  final String peerId;
  final String text;
  final DateTime timestamp;
  final bool isMe;
  const ChatMessage({required this.peerId, required this.text, required this.timestamp, required this.isMe});
}

class _CallScreenState extends State<CallScreen> {
  final _signaling = SignalingService();
  final _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, MediaStream?> _remotes = {};
  bool _isMicOn = true, _isCamOn = true;

  final List<ChatMessage> _messages = [];
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _chatOpen = false;
  int _unreadCount = 0;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    try {
      await _localRenderer.initialize();

      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}},
        });
        _localRenderer.srcObject = _localStream;
      } catch (mediaError) {
        _localStream = null;
        _localRenderer.srcObject = null;
      }

      _setupHandlers();
      await Future.delayed(const Duration(milliseconds: 300));
      _signaling.joinRoom(widget.roomCode);
    } catch (e, st) {
    }
  }

  void _setupHandlers() {
    _signaling.onRoomJoined((data) {
      final peers = List<String>.from(data['peers'] ?? []);
      if (widget.isCreator) {
        for (final p in peers) _initiateConnection(p);
      }
    });

    _signaling.onPeerJoined((data) {
      final peer = data['peerId'] as String;
      if (widget.isCreator) {
        _initiateConnection(peer);
      }
    });

    _signaling.onSignal((data) async {
      final from = data['from'] as String;
      final type = data['type'] as String;
      final sdp = (data['signal'] as Map)['sdp'] as String;

      if (type == 'offer') await _handleOffer(from, sdp);
      else if (type == 'answer') await _handleAnswer(from, sdp);
    });

    _signaling.onIceCandidate((data) async {
      final from = data['from'] as String;
      final cand = Map<String, dynamic>.from(data['candidate']);
      final pc = _pcs[from];
      if (pc != null) {
        try {
          await pc.addCandidate(RTCIceCandidate(
            cand['candidate'] as String?,
            cand['sdpMid'] as String?,
            (cand['sdpMLineIndex'] ?? cand['sdpMlineIndex']) as int?,
          ));
        } catch (e) {
        }
      }
    });

    _signaling.onPeerLeft((data) {
      final p = data['peerId'] as String;
      _cleanup(p);
    });

    _signaling.onChatMessage((data) {
      final msg = ChatMessage(
        peerId: data['from'] as String,
        text: data['text'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
        isMe: false,
      );
      if (mounted) {
        setState(() {
          _messages.add(msg);
          if (!_chatOpen) _unreadCount++;
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        });
      }
    });

  }

  Future<void> _initiateConnection(String remoteId) async {
    if (_pcs.containsKey(remoteId)) return;
    
    final pc = await _createPC(remoteId);
    final offer = await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': true});
    await pc.setLocalDescription(offer);
    
    _signaling.sendSignal(
      to: remoteId, from: widget.peerId,
      signal: {'type': offer.type, 'sdp': offer.sdp}, type: 'offer',
    );
  }

  Future<void> _handleOffer(String from, String sdp) async {
    final pc = await _createPC(from);
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _signaling.sendSignal(
      to: from, from: widget.peerId,
      signal: {'type': answer.type, 'sdp': answer.sdp}, type: 'answer',
    );
  }

  Future<void> _handleAnswer(String from, String sdp) async {
    final pc = _pcs[from];
    if (pc != null) {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    }
  }

  Future<RTCPeerConnection> _createPC(String peerId) async {
    if (_pcs.containsKey(peerId)) return _pcs[peerId]!;
    
    final pc = await createPeerConnection(_iceConfig);
    _pcs[peerId] = pc;

    if (_localStream != null) {
      _localStream!.getTracks().forEach((t) => pc.addTrack(t, _localStream!));
    }

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        if (mounted) setState(() => _remotes[peerId] = event.streams[0]);
      }
    };

    pc.onIceCandidate = (c) {
      if (c != null) {
        _signaling.sendIceCandidate(
          to: peerId, from: widget.peerId,
          candidate: {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
        );
      }
    };

    pc.onConnectionState = (s) => {};
    pc.onIceConnectionState = (s) => {};

    return pc;
  }

  void _cleanup(String p) {
    _pcs[p]?.close();
    _pcs.remove(p);
    _remotes.remove(p);
    if (mounted) setState(() {});
  }

  void _toggleMic() { setState(() => _isMicOn = !_isMicOn); _localStream?.getAudioTracks().forEach((t) => t.enabled = _isMicOn); }
  void _toggleCam() { setState(() => _isCamOn = !_isCamOn); _localStream?.getVideoTracks().forEach((t) => t.enabled = _isCamOn); }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _signaling.currentRoomCode == null) return;
    _signaling.sendChatMessage(roomCode: _signaling.currentRoomCode!, from: widget.peerId, text: text);
    _messages.add(ChatMessage(peerId: widget.peerId, text: text, timestamp: DateTime.now(), isMe: true));
    _chatCtrl.clear();
    if (mounted) setState(() {
      _unreadCount = 0;
      Future.delayed(const Duration(milliseconds: 100), () { if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); });
    });
  }
  
  void _leave() {
    _signaling.leaveRoom();
    _pcs.forEach((_, pc) => pc.close());
    _localStream?.getTracks().forEach((t) => t.stop());
    _localRenderer.dispose();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() { _leave(); super.dispose(); }

  /*build*/
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 80),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _calculateMaxVideoWidth(context),
                ),
                child: _remotes.isNotEmpty
                    ? GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _remotes.length <= 2 ? 1 : 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 3 / 4,
                        ),
                        itemCount: _remotes.length,
                        itemBuilder: (_, index) {
                          return _RemoteView(
                            stream: _remotes.values.elementAt(index),
                          );
                        },
                      )
                    : const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Ожидание участников...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),

          _buildLocalVideoPreview(),

          _buildChatToggleButton(),

          if (_chatOpen) _buildChatWindow(),

          _buildControlPanel(),

          _buildRoomCodeBadge(),
        ],
      ),
    );
  }

  double _calculateMaxVideoWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final calculatedWidth = screenWidth * 0.8;
    return calculatedWidth > 600 ? 600.0 : calculatedWidth;
  }

  Widget _buildLocalVideoPreview() {
    return Positioned(
      top: 50,
      right: 20,
      child: Container(
        width: 110,
        height: 145,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white30, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: RTCVideoView(
            _localRenderer,
            mirror: true,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  Widget _buildChatToggleButton() {
    return Positioned(
      bottom: 90,
      right: 20,
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _chatOpen = !_chatOpen;
                  if (_chatOpen) _unreadCount = 0;
                });
              },
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_unreadCount > 0 && !_chatOpen)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatWindow() {
    return Positioned(
      bottom: 150,
      right: 20,
      child: Container(
        width: 320,
        height: 380,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Чат комнаты',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _chatOpen = false),
                    child: Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (_, index) {
                  final message = _messages[index];
                  return _buildChatMessageItem(message);
                },
              ),
            ),

            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatCtrl,
                      onSubmitted: (_) => _sendChat(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Написать сообщение...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blue),
                    onPressed: _sendChat,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatMessageItem(ChatMessage message) {
    final isMe = message.isMe;
    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isMe ? Colors.blue[700] : Colors.grey[700];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 12),
              ),
            ),
            child: Text(
              message.text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(color: Colors.grey[500], fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildControlPanel() {
    return Positioned(
      bottom: 30,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlBtn(
            icon: _isCamOn ? Icons.videocam : Icons.videocam_off,
            onTap: _toggleCam,
            color: _isCamOn ? Colors.grey : Colors.red,
          ),
          const SizedBox(width: 32),
          _ControlBtn(
            icon: Icons.call_end,
            onTap: _leave,
            color: Colors.red,
            size: 56,
          ),
          const SizedBox(width: 32),
          _ControlBtn(
            icon: _isMicOn ? Icons.mic : Icons.mic_off,
            onTap: _toggleMic,
            color: _isMicOn ? Colors.grey : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCodeBadge() {
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              widget.roomCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteView extends StatefulWidget {
  final MediaStream? stream;
  final int peerIndex;
  
  const _RemoteView({this.stream, this.peerIndex = 0});
  
  @override
  State<_RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<_RemoteView> {
  final _renderer = RTCVideoRenderer();
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  @override
  void didUpdateWidget(_RemoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stream != oldWidget.stream && _renderer != null && widget.stream != null) {
      _renderer.srcObject = widget.stream;
    }
  }

  Future<void> _initRenderer() async {
    if (widget.stream == null) {
      _isReady = false;
      return;
    }
    
    try {
      await _renderer.initialize();
      _renderer.srcObject = widget.stream;
      if (mounted) setState(() => _isReady = true);
    } catch (e) {
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || widget.stream == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.grey[900]!, Colors.grey[800]!],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                size: 48,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Участник ${widget.peerIndex + 1}',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Colors.green[400]),
                  const SizedBox(width: 4),
                  Text(
                    'Подключён',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: RTCVideoView(
          _renderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final double size;
  
  const _ControlBtn({
    required this.icon,
    required this.onTap,
    this.color = Colors.grey,
    this.size = 50,
  });
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}