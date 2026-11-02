package com.jianyin.jianyin_app.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

/**
 * 流式 PCM 播放桥（Android）。
 *
 * 契约：只接受 **PCM s16le / 16 kHz / mono**（见 docs/api/protocol.md）。
 * 实现：`AudioTrack(MODE_STREAM)` 直写字节，不做文件落地、不攒整句；
 * `bufferedFrames` 回传原生缓冲水位，供 Dart 侧抖动缓冲判定欠载。
 *
 * 与 `vision/MediaPipeVisionPlugin` 同构：薄 MethodChannel + 明确字节契约。
 */
class PcmPlayerPlugin : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "jianyin/pcm_player"

        /** 最小缓冲：兼顾低延迟与小抖动（100 ms 片 ≈ 3200 字节）。 */
        private const val MIN_BUFFER_BYTES = 16 * 1024
    }

    private var track: AudioTrack? = null
    private var sampleRate = 16000
    private var channels = 1

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> open(call, result)
            "write" -> write(call, result)
            "bufferedFrames" -> result.success(bufferedFrames())
            "flush" -> {
                flush()
                result.success(null)
            }
            "close" -> {
                close()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        sampleRate = call.argument<Int>("sampleRate") ?: 16000
        channels = call.argument<Int>("channels") ?: 1
        close()

        val channelMask =
            if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(sampleRate)
            .setChannelMask(channelMask)
            .build()
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            channelMask,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufferSize = max(minBuffer, MIN_BUFFER_BYTES)

        val created = try {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setAudioFormat(format)
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            null
        }

        if (created == null || created.state != AudioTrack.STATE_INITIALIZED) {
            created?.release()
            result.success(false)
            return
        }
        created.play()
        track = created
        result.success(true)
    }

    private fun write(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val active = track
        if (bytes == null || bytes.isEmpty() || active == null) {
            result.success(null)
            return
        }
        try {
            // 非阻塞写入：背压由 Dart 侧水位与丢片策略处理。
            if (active.playState != AudioTrack.PLAYSTATE_PLAYING) active.play()
            active.write(bytes, 0, bytes.size, AudioTrack.WRITE_NON_BLOCKING)
        } catch (e: Exception) {
            // 写入失败不应中断会话；下一次写入或水位查询会暴露真实状态。
        }
        result.success(null)
    }

    private fun bufferedFrames(): Int = try {
        track?.bufferSizeInFrames ?: 0
    } catch (e: Exception) {
        0
    }

    private fun flush() {
        try {
            track?.pause()
            track?.flush()
        } catch (e: Exception) {
            // 忽略：Flushing 不应阻断会话拆除。
        }
    }

    private fun close() {
        try {
            track?.pause()
            track?.flush()
            track?.release()
        } catch (e: Exception) {
            // 忽略：释放失败也不能影响 App 退出。
        }
        track = null
    }
}