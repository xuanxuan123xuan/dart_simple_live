package com.aaassseee.screen_brightness_android.stream_handler

import io.flutter.plugin.common.EventChannel

open class BaseStreamHandler: EventChannel.StreamHandler {

    var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}