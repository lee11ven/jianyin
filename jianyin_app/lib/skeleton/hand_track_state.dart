import '../config/perception_thresholds.dart';
import '../envelope/landmark_point.dart';
import '../native/mediapipe_vision.dart';
import 'hand_types.dart';

class _Track {
  _Track({
    required this.id,
    required this.label,
    required this.wrist,
  });

  final int id;
  HandState label;
  LandmarkPoint wrist;
  int lockFrames = 0;
  int conflictFrames = 0;
}

/// Wrist nearest-neighbor tracks + label fusion for fixed 42 slots.
class HandSlotFuser {
  HandSlotFuser({this.thresholds = PerceptionThresholds.defaults});

  final PerceptionThresholds thresholds;
  final List<_Track> _tracks = [];
  int _nextId = 1;

  /// Returns left/right 21-point lists (null = empty slot / rejected).
  ({List<LandmarkPoint>? left, List<LandmarkPoint>? right, HandState state})
      fuse({
    required List<DetectedHand> detections,
    required HandState handStatePrior,
  }) {
    final assigned = <_Track?>[];
    for (final det in detections) {
      if (det.landmarks.isEmpty) {
        assigned.add(null);
        continue;
      }
      final wrist = det.landmarks[0];
      final track = _associate(wrist);
      final candidate = _candidateLabel(det, handStatePrior);
      if (track.lockFrames >= thresholds.nLock) {
        if (candidate != HandState.none &&
            candidate != track.label &&
            track.label != HandState.none) {
          track.conflictFrames++;
        } else {
          track.conflictFrames = 0;
        }
      } else {
        final fused = _fuseLabel(
          locked: track.label,
          lockFrames: track.lockFrames,
          handState: handStatePrior,
          handedness: candidate,
          score: det.score,
        );
        if (fused != HandState.none) {
          track.label = fused;
          track.lockFrames++;
        }
        track.conflictFrames = 0;
      }
      track.wrist = wrist;
      assigned.add(track);
    }

    // Drop stale tracks not seen this frame.
    final live = assigned.whereType<_Track>().toSet();
    _tracks.removeWhere((t) => !live.contains(t));

    List<LandmarkPoint>? left;
    List<LandmarkPoint>? right;
    var dualConflict = false;

    for (var i = 0; i < detections.length; i++) {
      final track = assigned[i];
      if (track == null) continue;
      if (track.conflictFrames >= thresholds.nConflict) {
        continue;
      }
      final pts = detections[i].landmarks;
      if (track.label == HandState.left) {
        if (left != null) {
          dualConflict = true;
          break;
        }
        left = pts;
      } else if (track.label == HandState.right) {
        if (right != null) {
          dualConflict = true;
          break;
        }
        right = pts;
      }
    }

    if (dualConflict) {
      return (left: null, right: null, state: HandState.none);
    }

    // Single-hand prior: only fill the requested slot.
    if (handStatePrior == HandState.left) {
      right = null;
    } else if (handStatePrior == HandState.right) {
      left = null;
    }

    final state = _stateFromSlots(left, right, handStatePrior);
    return (left: left, right: right, state: state);
  }

  void reset() {
    _tracks.clear();
    _nextId = 1;
  }

  _Track _associate(LandmarkPoint wrist) {
    _Track? best;
    final maxDistSq = thresholds.trackAssociateDist * thresholds.trackAssociateDist;
    var bestDist = maxDistSq;
    for (final t in _tracks) {
      final d = _distSq(t.wrist, wrist);
      if (d < bestDist) {
        bestDist = d;
        best = t;
      }
    }
    if (best != null) return best;
    final created = _Track(id: _nextId++, label: HandState.none, wrist: wrist);
    _tracks.add(created);
    return created;
  }

  HandState _candidateLabel(DetectedHand det, HandState prior) {
    if (det.score < thresholds.pHand) {
      if (prior == HandState.left || prior == HandState.right) return prior;
      return HandState.none;
    }
    final name = det.handedness.toLowerCase();
    if (name.startsWith('left')) return HandState.left;
    if (name.startsWith('right')) return HandState.right;
    return HandState.none;
  }

  HandState _fuseLabel({
    required HandState locked,
    required int lockFrames,
    required HandState handState,
    required HandState handedness,
    required double score,
  }) {
    if (lockFrames >= thresholds.nLock && locked != HandState.none) {
      return locked;
    }
    if (handState == HandState.left || handState == HandState.right) {
      return handState;
    }
    if (score >= thresholds.pHand &&
        (handedness == HandState.left || handedness == HandState.right)) {
      return handedness;
    }
    return locked;
  }

  HandState _stateFromSlots(
    List<LandmarkPoint>? left,
    List<LandmarkPoint>? right,
    HandState prior,
  ) {
    final hasL = left != null;
    final hasR = right != null;
    if (hasL && hasR) return HandState.both;
    if (hasL) return HandState.left;
    if (hasR) return HandState.right;
    return prior == HandState.none ? HandState.none : HandState.none;
  }

  static double _distSq(LandmarkPoint a, LandmarkPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy;
  }
}
