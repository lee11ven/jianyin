/// Cold-start defaults for client perception MVP (tunable later).
class PerceptionThresholds {
  const PerceptionThresholds({
    this.vAnchor = 0.5,
    this.nAnchor = 10,
    this.wMin = 0.08,
    this.sMin = 80.0,
    this.tOnset = 12.0,
    this.tQuietMs = 800,
    this.deltaIdleMs = 120,
    this.deltaActiveMs = 40,
    this.nStableHand = 3,
    this.vMinJoint = 0.5,
    this.rMinValid = 0.55,
    this.pHand = 0.6,
    this.nLock = 5,
    this.nConflict = 4,
    this.trackAssociateDist = 0.12,
    this.smoothAlpha = 0.45,
    this.palmVisibilityScale = 0.85,
  });

  /// Nose / shoulder minimum visibility to build body axes.
  final double vAnchor;

  /// Consecutive missing-anchor ticks before `hint.show_upper_body`.
  final int nAnchor;

  /// Minimum shoulder width in image-normalized units.
  final double wMin;

  /// Laplacian variance floor; below → omit hands this tick.
  final double sMin;

  /// Mean abs Y-diff to enter Active.
  final double tOnset;

  /// Quiet duration to return Idle.
  final int tQuietMs;

  /// Min interval between Idle presence-probe ticks (~8 Hz).
  final int deltaIdleMs;

  /// Min interval between Active ticks (~25 Hz).
  final int deltaActiveMs;

  /// Frames required to change `hand_state`.
  final int nStableHand;

  /// Per-joint visibility for Hands packing.
  final double vMinJoint;

  /// Fraction of valid joints required per hand slot.
  final double rMinValid;

  /// MediaPipe handedness probability floor.
  final double pHand;

  /// Frames before track label is considered locked.
  final int nLock;

  /// Consecutive label conflicts before rejecting the slot.
  final int nConflict;

  /// Max image distance to associate wrist to an existing track.
  final double trackAssociateDist;

  /// Exponential smooth factor for valid hand joints.
  final double smoothAlpha;

  /// Palm = wrist with reduced visibility in path MVP.
  final double palmVisibilityScale;

  static const defaults = PerceptionThresholds();
}
