import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/envelope/catalog.dart';
import 'package:jianyin_app/envelope/csl_channels.dart';
import 'package:jianyin_app/envelope/envelope_packer.dart';
import 'package:jianyin_app/envelope/landmark_point.dart';
import 'package:jianyin_app/perception/perception_pipeline.dart';
import 'package:jianyin_app/skeleton/hand_types.dart';

void main() {
  test('catalog locks 42-point packing and tip locals', () {
    expect(EnvelopeCatalog.packingLength, 42);
    expect(EnvelopeCatalog.slot(left: true, local: 0), 0);
    expect(EnvelopeCatalog.slot(left: false, local: 0), 21);
    expect(EnvelopeCatalog.jointId(left: true, local: 8), 'L.index.tip');
    expect(EnvelopeCatalog.jointId(left: false, local: 4), 'R.thumb.tip');
    expect(EnvelopeCatalog.tipLocals['index'], 8);
    expect(EnvelopeCatalog.sites, contains('forehead'));
  });

  test('packer projects csl_channels_v1 with optional path gap', () {
    const packer = DefaultEnvelopePacker();
    final msg = packer.pack(
      ts: 100,
      sessionId: 'sess-test',
      path: const PathChannel(space: 'image', anchor: false, gap: true),
    );
    final json = msg.toJson();
    expect(json['schema'], 'csl_channels_v1');
    expect(json['path']['gap'], true);
    expect(json.containsKey('hands'), false);
    expect(json.containsKey('body'), false);
  });

  test('packHands42 keeps left then right slots', () {
    final left = List<LandmarkPoint>.generate(
      21,
      (i) => LandmarkPoint(x: i.toDouble(), y: 0, z: 0, v: 1),
    );
    final packed = packHands42(left: left);
    expect(packed.points.length, 42);
    expect(packed.points[8].x, 8);
    expect(packed.points[21].v, 0);
  });

  test('perception pipeline stub emits landmarks without throwing', () async {
    final pipeline = PerceptionPipeline();
    final msg = await pipeline.tick(
      ts: 1,
      sessionId: 'sess',
      frame: Object(),
      handStatePrior: HandState.none,
      forcePathGap: true,
    );
    expect(msg.toJson()['schema'], CslChannelsLandmarks.schema);
    expect(msg.path?.gap, true);
    await pipeline.dispose();
  });
}
