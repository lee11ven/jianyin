/**
 * Recognition pipeline stub.
 *
 * Accepts landmark uplink for session activity. Does **not** emit mock
 * captions — real CSL window / model wiring replaces this later.
 */
export class RecognitionPipeline {
  constructor({ onResult }) {
    /** @type {(result: object) => void} */
    this.onResult = onResult;
  }

  reset(_sessionId) {
    // no per-session mock state
  }

  /**
   * @param {string} _sessionId
   * @param {object} _landmarksMsg
   */
  ingest(_sessionId, _landmarksMsg) {
    // Intentionally empty: no round-robin / fake gesture text.
  }
}
