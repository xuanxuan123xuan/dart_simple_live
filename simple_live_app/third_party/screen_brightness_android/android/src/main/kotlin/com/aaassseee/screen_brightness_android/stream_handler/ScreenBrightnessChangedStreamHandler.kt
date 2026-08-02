package com.aaassseee.screen_brightness_android.stream_handler

import io.flutter.plugin.common.EventChannel

class ScreenBrightnessChangedStreamHandler(
    private val onListenStart: ((eventSink: EventChannel.EventSink) -> Unit)?,
) : BaseStreamHandler() {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        super.onListen(arguments, events)
        val eventSink = eventSink ?: return
        onListenStart?.invoke(eventSink)
    }

    fun addScreenBrightnessToEventSink(brightness: Double) {
        val eventSink = eventSink ?: return
        eventSink.success(brightness)
    }
}