import 'csl_channels.dart';

/// Unique module that projects the three perception branches into
/// `schema: csl_channels_v1` landmarks JSON for WS uplink.
///
/// Same-tick order (locked): body → trajectory → skeleton → pack.
abstract class EnvelopePacker {
  /// Build one uplink message. Omit empty optional channels.
  CslChannelsLandmarks pack({
    required int ts,
    required String sessionId,
    HandsChannel? hands,
    PathChannel? path,
    BodyChannel? body,
    NonmanualChannel? nonmanual,
  });
}

/// Default packer: identity projection, no extra inference.
class DefaultEnvelopePacker implements EnvelopePacker {
  const DefaultEnvelopePacker();

  @override
  CslChannelsLandmarks pack({
    required int ts,
    required String sessionId,
    HandsChannel? hands,
    PathChannel? path,
    BodyChannel? body,
    NonmanualChannel? nonmanual,
  }) {
    return CslChannelsLandmarks(
      ts: ts,
      sessionId: sessionId,
      hands: hands,
      path: path,
      body: body,
      nonmanual: nonmanual,
    );
  }
}
