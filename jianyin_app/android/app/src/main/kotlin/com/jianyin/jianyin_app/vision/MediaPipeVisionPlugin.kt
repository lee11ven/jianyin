package com.jianyin.jianyin_app.vision

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

/**
 * Dual-platform MethodChannel handler (Android).
 * Contract: format=rgba contiguous RGBA8888; IMAGE mode Pose + Hands.
 *
 * MediaPipe Tasks Vision ships ARM `.so` only — x86/x86_64 emulators must
 * fail soft (no process crash) so camera UI still runs.
 */
class MediaPipeVisionPlugin(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    private var pose: PoseLandmarker? = null
    private var hands: HandLandmarker? = null
    private var loadFailed: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ensureReady" -> {
                    val poseAsset = call.argument<String>("poseAsset")
                        ?: "assets/ml/pose_landmarker_lite.task"
                    val handsAsset = call.argument<String>("handsAsset")
                        ?: "assets/ml/hand_landmarker.task"
                    ensureReady(poseAsset, handsAsset)
                    result.success(null)
                }
                "detectPose" -> result.success(detectPose(call))
                "detectHands" -> result.success(detectHands(call))
                "dispose" -> {
                    disposeLandmarkers()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            // UnsatisfiedLinkError is an Error, not Exception — must catch Throwable.
            Log.e(TAG, "MediaPipe call failed: ${call.method}", t)
            loadFailed = t.message ?: t.javaClass.simpleName
            result.error("mediapipe", loadFailed, t.javaClass.name)
        }
    }

    private fun ensureReady(poseAsset: String, handsAsset: String) {
        if (pose != null && hands != null) return
        if (loadFailed != null) {
            throw IllegalStateException(loadFailed)
        }
        if (!isArmAbiSupported()) {
            val abis = Build.SUPPORTED_ABIS.joinToString()
            throw UnsatisfiedLinkError(
                "MediaPipe Tasks Vision has no x86/x86_64 native libs " +
                    "(device ABIs: $abis). Use an arm64 device or ARM system image.",
            )
        }

        val poseBuffer = loadModelBuffer(poseAsset)
        val handsBuffer = loadModelBuffer(handsAsset)

        pose = PoseLandmarker.createFromOptions(
            context,
            PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder().setModelAssetBuffer(poseBuffer).build(),
                )
                .setRunningMode(RunningMode.IMAGE)
                .setNumPoses(1)
                .build(),
        )

        hands = HandLandmarker.createFromOptions(
            context,
            HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(
                    BaseOptions.builder().setModelAssetBuffer(handsBuffer).build(),
                )
                .setRunningMode(RunningMode.IMAGE)
                .setNumHands(2)
                .build(),
        )
    }

    private fun isArmAbiSupported(): Boolean {
        return Build.SUPPORTED_ABIS.any { abi ->
            abi == "arm64-v8a" || abi == "armeabi-v7a" || abi == "armeabi"
        }
    }

    private fun loadModelBuffer(flutterAssetKey: String): ByteBuffer {
        val assetPath = "flutter_assets/$flutterAssetKey"
        val bytes = context.assets.open(assetPath).use { it.readBytes() }
        return ByteBuffer.allocateDirect(bytes.size).apply {
            put(bytes)
            rewind()
        }
    }

    private fun detectPose(call: MethodCall): Map<String, Any>? {
        val landmarker = pose ?: return null
        val image = rgbaToBitmap(call) ?: return null
        val mpImage = BitmapImageBuilder(image).build()
        val detection = landmarker.detect(mpImage)
        if (detection.landmarks().isEmpty()) return null
        val lm = detection.landmarks()[0]
        val out = ArrayList<Map<String, Double>>(lm.size)
        for (p in lm) {
            val vis = optionalFloat(p.visibility())
            val pres = optionalFloat(p.presence())
            out.add(
                mapOf(
                    "x" to p.x().toDouble(),
                    "y" to p.y().toDouble(),
                    "z" to p.z().toDouble(),
                    "v" to minOf(vis, pres).toDouble().coerceIn(0.0, 1.0),
                ),
            )
        }
        return mapOf("landmarks" to out)
    }

    private fun detectHands(call: MethodCall): Map<String, Any>? {
        val landmarker = hands ?: return null
        val image = rgbaToBitmap(call) ?: return null
        val mpImage = BitmapImageBuilder(image).build()
        val detection = landmarker.detect(mpImage)
        val landmarksList = detection.landmarks()
        if (landmarksList.isEmpty()) return null
        val handednessList = detection.handednesses()
        val handsOut = ArrayList<Map<String, Any>>(landmarksList.size)
        for (i in landmarksList.indices) {
            val lm = landmarksList[i]
            val points = ArrayList<Map<String, Double>>(lm.size)
            for (p in lm) {
                val vis = optionalFloat(p.visibility())
                val pres = optionalFloat(p.presence())
                points.add(
                    mapOf(
                        "x" to p.x().toDouble(),
                        "y" to p.y().toDouble(),
                        "z" to p.z().toDouble(),
                        "v" to minOf(vis, pres).toDouble().coerceIn(0.0, 1.0),
                    ),
                )
            }
            var label = "Right"
            var score = 0.0
            if (i < handednessList.size && handednessList[i].isNotEmpty()) {
                val cat = handednessList[i][0]
                label = cat.categoryName()
                score = cat.score().toDouble()
            }
            handsOut.add(
                mapOf(
                    "landmarks" to points,
                    "handedness" to label,
                    "score" to score,
                ),
            )
        }
        return mapOf("hands" to handsOut)
    }

    private fun rgbaToBitmap(call: MethodCall): Bitmap? {
        val width = call.argument<Int>("width") ?: return null
        val height = call.argument<Int>("height") ?: return null
        val bytes = call.argument<ByteArray>("bytes") ?: return null
        if (bytes.size < width * height * 4) return null
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val pixels = IntArray(width * height)
        var i = 0
        var p = 0
        while (i + 3 < bytes.size && p < pixels.size) {
            val r = bytes[i].toInt() and 0xff
            val g = bytes[i + 1].toInt() and 0xff
            val b = bytes[i + 2].toInt() and 0xff
            val a = bytes[i + 3].toInt() and 0xff
            pixels[p] = (a shl 24) or (r shl 16) or (g shl 8) or b
            i += 4
            p++
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap
    }

    private fun optionalFloat(value: java.util.Optional<Float>?): Float {
        if (value == null) return 1f
        return if (value.isPresent) value.get() else 1f
    }

    private fun disposeLandmarkers() {
        pose?.close()
        hands?.close()
        pose = null
        hands = null
    }

    companion object {
        const val CHANNEL = "jianyin/mediapipe_vision"
        private const val TAG = "MediaPipeVision"
    }
}
