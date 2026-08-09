package com.tomoread.reader.tomoread

import android.view.KeyEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class VolumeControlPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isIntercepting = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "dev.tomoread/volume_control",
        ).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(
            binding.binaryMessenger,
            "dev.tomoread/volume_events",
        ).also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        isIntercepting = false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enableInterception" -> {
                isIntercepting = true
                result.success(null)
            }
            "disableInterception" -> {
                isIntercepting = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun processKeyDown(keyCode: Int): Boolean {
        if (!isIntercepting) return false
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> eventSink?.success("up")
            KeyEvent.KEYCODE_VOLUME_DOWN -> eventSink?.success("down")
            else -> return false
        }
        return true
    }
}
