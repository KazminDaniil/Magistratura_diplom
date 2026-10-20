import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  Map<String, dynamic> get iceConfig => {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };
  //параметры захвата камеры и микро
  final Map<String, dynamic> _mediaConstraints = {
    'audio': true,
    'video': {
      'facingMode': 'user',
      'width': {'ideal': 1280},
      'height': {'ideal': 720},
    },
  };
  //запрос на получение камеры и микро
  Future<MediaStream> getLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);
    return _localStream!;
  }

  Future<RTCPeerConnection> initializePeerConnection() async {
    _peerConnection = await createPeerConnection(iceConfig);

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });
    //почему здесь пусто??? не знаю
    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate != null) {
      }
    };

    _peerConnection?.onTrack = (event) {
    };

    _peerConnection?.onConnectionState = (state) {
    };

    return _peerConnection!;
  }
  //генерация SDP (текстовое описание кодеков, битрейта, разрешения, фпса)
  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }
  //генерация ответа на SDP
  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription desc) async {
    await _peerConnection!.setRemoteDescription(desc);
  }
  //добавление сетевого адреса собеседника
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection!.addCandidate(candidate);
  }
  //рендер
  Future<RTCVideoRenderer> getRemoteRenderer(String peerId) async {
    if (!_remoteRenderers.containsKey(peerId)) {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _remoteRenderers[peerId] = renderer;
    }
    return _remoteRenderers[peerId]!;
  }

  void setRemoteStream(String peerId, MediaStream stream) {
    _remoteRenderers[peerId]?.srcObject = stream;
  }

  Future<void> disposePeer(String peerId) async {
    await _remoteRenderers[peerId]?.dispose();
    _remoteRenderers.remove(peerId);
  }

  Future<void> close() async {
    for (final r in _remoteRenderers.values) await r.dispose();
    _remoteRenderers.clear();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    await _peerConnection?.close();
  }

  MediaStream? get localStream => _localStream;
  RTCPeerConnection? get peerConnection => _peerConnection;
  Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;
}