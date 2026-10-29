/// Downlink / control events from `/ws/app`.
sealed class WsEvent {
  const WsEvent();
}

class WsConnected extends WsEvent {
  const WsConnected({required this.sessionId});
  final String sessionId;
}

class WsDisconnected extends WsEvent {
  const WsDisconnected({this.reason});
  final String? reason;
}

class WsReconnecting extends WsEvent {
  const WsReconnecting({required this.attempt, required this.delay});
  final int attempt;
  final Duration delay;
}

class WsRecognition extends WsEvent {
  const WsRecognition({
    required this.sessionId,
    required this.utteranceId,
    required this.text,
    required this.confidence,
    required this.glossIds,
    required this.vocabVersion,
    required this.ts,
  });

  final String sessionId;
  final String utteranceId;
  final String text;
  final double confidence;
  final List<String> glossIds;
  final String? vocabVersion;
  final int ts;

  factory WsRecognition.fromJson(Map<String, dynamic> json) {
    final gloss = json['glossIds'];
    return WsRecognition(
      sessionId: '${json['sessionId'] ?? ''}',
      utteranceId: '${json['utteranceId'] ?? ''}',
      text: '${json['text'] ?? ''}',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      glossIds: gloss is List
          ? gloss.map((e) => '$e').toList(growable: false)
          : const [],
      vocabVersion: json['vocabVersion'] as String?,
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

class WsSpeechMeta extends WsEvent {
  const WsSpeechMeta({
    required this.sessionId,
    required this.utteranceId,
    required this.text,
    required this.delivery,
    required this.accepted,
  });

  final String sessionId;
  final String utteranceId;
  final String text;
  final String delivery;
  final bool accepted;

  factory WsSpeechMeta.fromJson(Map<String, dynamic> json) {
    final delivery = '${json['delivery'] ?? ''}';
    final hasInline = json.containsKey('audioBase64') ||
        delivery == 'inline_fallback';
    final accepted = delivery == 'ws_binary_audio' && !hasInline;
    return WsSpeechMeta(
      sessionId: '${json['sessionId'] ?? ''}',
      utteranceId: '${json['utteranceId'] ?? ''}',
      text: '${json['text'] ?? ''}',
      delivery: delivery,
      accepted: accepted,
    );
  }
}

class WsAudioHeader extends WsEvent {
  const WsAudioHeader({
    required this.sessionId,
    required this.utteranceId,
    required this.seq,
    required this.mimeType,
    required this.sampleRate,
    required this.channels,
    required this.encoding,
    required this.last,
  });

  final String sessionId;
  final String utteranceId;
  final int seq;
  final String mimeType;
  final int sampleRate;
  final int channels;
  final String encoding;
  final bool last;

  factory WsAudioHeader.fromJson(Map<String, dynamic> json) {
    return WsAudioHeader(
      sessionId: '${json['sessionId'] ?? ''}',
      utteranceId: '${json['utteranceId'] ?? ''}',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      mimeType: '${json['mimeType'] ?? 'audio/pcm'}',
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 16000,
      channels: (json['channels'] as num?)?.toInt() ?? 1,
      encoding: '${json['encoding'] ?? 's16le'}',
      last: json['last'] == true,
    );
  }
}

class WsAudioBinary extends WsEvent {
  const WsAudioBinary({
    required this.header,
    required this.bytes,
  });

  final WsAudioHeader header;
  final List<int> bytes;
}

class WsErrorEvent extends WsEvent {
  const WsErrorEvent({
    required this.code,
    required this.message,
    this.sessionId,
  });

  final String code;
  final String message;
  final String? sessionId;

  factory WsErrorEvent.fromJson(Map<String, dynamic> json) {
    return WsErrorEvent(
      code: '${json['code'] ?? 'internal'}',
      message: '${json['message'] ?? ''}',
      sessionId: json['sessionId'] as String?,
    );
  }
}

class WsSessionLifecycle extends WsEvent {
  const WsSessionLifecycle({required this.type, required this.sessionId});
  final String type; // session.started | session.stopped
  final String sessionId;
}
