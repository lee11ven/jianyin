import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/envelope/catalog.dart';
import 'package:jianyin_app/envelope/csl_channels.dart';
import 'package:jianyin_app/envelope/envelope_assembler.dart';
import 'package:jianyin_app/envelope/landmark_point.dart';
import 'package:jianyin_app/skeleton/hand_types.dart';

void main() {
  test('catalog locks 46 bones and middle/ring metacarpal edges', () {
    expect(EnvelopeCatalog.boneLocals.length, 23);
    expect(EnvelopeCatalog.bonesLeft.length, 23);
    expect(EnvelopeCatalog.bonesRight.length, 23);

    final catalog = EnvelopeCatalog.buildCatalogJson();
    final leftBones =
        (catalog['hands'] as Map)['left']['bones'] as List<dynamic>;
    final rightBones =
        (catalog['hands'] as Map)['right']['bones'] as List<dynamic>;
    expect(leftBones.length + rightBones.length, 46);

    BoneSpec middle() => EnvelopeCatalog.boneLocals
        .firstWhere((b) => b.idSuffix == 'middle.metacarpal');
    BoneSpec ring() => EnvelopeCatalog.boneLocals
        .firstWhere((b) => b.idSuffix == 'ring.metacarpal');
    expect(middle().mediapipeEdge, isFalse);
    expect(ring().mediapipeEdge, isFalse);

    expect(catalog['pathPoints'], isNotEmpty);
    expect(catalog['bodyPoints'], hasLength(EnvelopeCatalog.bodyPoseIndex.length));
    expect(catalog['nonmanualQuantities'], EnvelopeCatalog.nonmanualQuantities);
  });

  test('assembleFrame expands 42 joints and 46 bones', () {
    const assembler = DefaultEnvelopeAssembler();
    final left = List<LandmarkPoint>.generate(
      21,
      (i) => LandmarkPoint(x: i.toDouble(), y: 1, z: 0, v: 1),
    );
    final frame = assembler.assembleFrame(
      ts: 42,
      handState: HandState.left,
      hands: packHands42(left: left),
      vMin: 0.5,
    );

    expect(frame, isNotNull);
    expect(frame!.left.joints, hasLength(21));
    expect(frame.right.joints, hasLength(21));
    expect(frame.left.bones, hasLength(23));
    expect(frame.right.bones, hasLength(23));
    expect(frame.left.present, isTrue);
    expect(frame.right.present, isFalse);
    expect(frame.left.bones.every((b) => b.valid == true), isTrue);
    expect(frame.right.bones.every((b) => b.valid == false), isTrue);
    expect(frame.relation.layout, 'left');
    expect(frame.left.joints[8].id, 'L.index.tip');
    expect(frame.left.joints[8].x, 8);
  });

  test('low visibility marks bone invalid', () {
    const assembler = DefaultEnvelopeAssembler();
    final left = List<LandmarkPoint>.generate(
      21,
      (i) => LandmarkPoint(
        x: 0,
        y: 0,
        z: 0,
        v: i == 8 ? 0.1 : 1.0,
      ),
    );
    final frame = assembler.assembleFrame(
      ts: 1,
      handState: HandState.left,
      hands: packHands42(left: left),
      vMin: 0.5,
    )!;

    final distal = frame.left.bones
        .firstWhere((b) => b.id == 'L.index.phalanx.distal');
    expect(distal.valid, isFalse);
    final proximal = frame.left.bones
        .firstWhere((b) => b.id == 'L.index.phalanx.proximal');
    expect(proximal.valid, isTrue);
  });

  test('handState none yields no frame', () {
    const assembler = DefaultEnvelopeAssembler();
    final frame = assembler.assembleFrame(
      ts: 1,
      handState: HandState.none,
      path: const PathChannel(space: 'image', anchor: false, gap: true),
    );
    expect(frame, isNull);
  });

  test('projectUplink omits bones and relation', () {
    const assembler = DefaultEnvelopeAssembler();
    final left = List<LandmarkPoint>.generate(
      21,
      (_) => const LandmarkPoint(x: 0.2, y: 0.3, z: 0, v: 0.9),
    );
    final frame = assembler.assembleFrame(
      ts: 9,
      handState: HandState.both,
      hands: packHands42(left: left, right: left),
      path: const PathChannel(space: 'body', anchor: true, gap: true),
    )!;
    final msg = assembler.projectUplink(
      frame: frame,
      sessionId: 'sess',
    );
    final json = msg.toJson();
    expect(json['schema'], CslChannelsLandmarks.schema);
    expect(json['hands']['points'], hasLength(42));
    expect(json.containsKey('relation'), isFalse);
    expect(json['hands'].containsKey('bones'), isFalse);
    expect(json['path']['gap'], isTrue);
  });
}
