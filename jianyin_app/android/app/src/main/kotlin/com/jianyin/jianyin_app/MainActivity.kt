package com.jianyin.jianyin_app

import com.jianyin.jianyin_app.audio.KeepAlivePlugin
import com.jianyin.jianyin_app.audio.PcmPlayerPlugin
import com.jianyin.jianyin_app.vision.MediaPipeVisionPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MediaPipeVisionPlugin.CHANNEL,
        ).setMethodCallHandler(MediaPipeVisionPlugin(applicationContext))
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PcmPlayerPlugin.CHANNEL,
        ).setMethodCallHandler(PcmPlayerPlugin())
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KeepAlivePlugin.CHANNEL,
        ).setMethodCallHandler(KeepAlivePlugin(applicationContext))
    }
}
