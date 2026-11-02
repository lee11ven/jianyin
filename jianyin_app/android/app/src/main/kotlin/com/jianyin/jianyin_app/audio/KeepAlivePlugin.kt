package com.jianyin.jianyin_app.audio

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 保活桥（Android）：把 Home 会话的前台服务开关暴露给 Dart。
 *
 * 契约：`start` 在 REST 建会话成功后调用；`stop` 在离开 Home / 退出应用时调用。
 * 非 Home 场景不得调用（对应 architecture.md「保活只绑 Home 会话」）。
 */
class KeepAlivePlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "jianyin/keepalive"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                try {
                    HomeSessionService.start(context)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "stop" -> {
                try {
                    HomeSessionService.stop(context)
                } catch (e: Exception) {
                    // 停止失败不应阻断拆除流程。
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}