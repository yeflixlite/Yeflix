package com.yeflix.app

import android.content.Context
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

class ExoPlayerPlatformView(
    private val context: Context,
    id: Int,
    private val messenger: BinaryMessenger,
    private val channelName: String
) : PlatformView, Player.Listener, MethodChannel.MethodCallHandler {

    private val playerView = PlayerView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        useController = false
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    }

    private val player = ExoPlayer.Builder(context)
        .setLoadControl(
            DefaultLoadControl.Builder()
                .setBufferDurationsMs(20_000, 50_000, 2_500, 4_000)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()
        )
        .build()
        .apply {
            addListener(this@ExoPlayerPlatformView)
        }

    private val container = FrameLayout(context).apply {
        addView(playerView)
    }

    private val channel = MethodChannel(messenger, channelName)
    private var released = false

    init {
        playerView.player = player
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSource" -> {
                val url = call.argument<String>("url") ?: ""
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val positionMs = call.argument<Int>("positionMs") ?: 0
                val mimeType = call.argument<String>("mimeType")
                if (url.isBlank()) {
                    result.error("no_url", "URL de origen vacía", null)
                    return
                }

                try {
                    val defaultUa = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                    val userAgent = headers["User-Agent"] ?: headers["user-agent"] ?: defaultUa

                    val httpFactory = DefaultHttpDataSource.Factory()
                        .setUserAgent(userAgent)
                        .setConnectTimeoutMs(15_000)
                        .setReadTimeoutMs(20_000)
                        .setAllowCrossProtocolRedirects(true)
                        .setKeepPostFor302Redirects(true)
                        .setDefaultRequestProperties(headers)

                    val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
                    val mediaItem = buildMediaItem(url, mimeType)
                    val mediaSource = DefaultMediaSourceFactory(dataSourceFactory)
                        .createMediaSource(mediaItem)

                    player.setMediaSource(mediaSource)
                    if (positionMs > 0) {
                        player.seekTo(positionMs.toLong())
                    }
                    player.prepare()
                    player.playWhenReady = true
                    result.success(null)
                } catch (t: Throwable) {
                    val msg = t.message ?: t.javaClass.simpleName
                    channel.invokeMethod("onPlayerError", "Error al inicializar reproductor: $msg")
                    result.error("init_error", msg, null)
                }
            }
            "play" -> {
                player.playWhenReady = true
                result.success(null)
            }
            "pause" -> {
                player.playWhenReady = false
                result.success(null)
            }
            "seek" -> {
                val positionMs = call.argument<Int>("positionMs") ?: 0
                player.seekTo(positionMs.toLong())
                result.success(null)
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                player.setVolume(volume.toFloat())
                result.success(null)
            }
            "positionMs" -> result.success(player.currentPosition)
            "durationMs" -> result.success(player.duration)
            "isPlaying" -> result.success(
                player.playWhenReady && player.playbackState == Player.STATE_READY
            )
            "dispose" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun buildMediaItem(url: String, explicitMimeType: String? = null): MediaItem {
        val uri = sourceUri(url)
        val builder = MediaItem.Builder().setUri(uri)
        if (!explicitMimeType.isNullOrBlank()) {
            builder.setMimeType(explicitMimeType)
        } else {
            val clean = url.substringBefore('?').substringBefore('#').lowercase()
            when {
                clean.endsWith(".m3u8") || clean.contains("/hls/") -> {
                    builder.setMimeType(MimeTypes.APPLICATION_M3U8)
                }
                clean.endsWith(".mpd") || clean.contains("/dash/") -> {
                    builder.setMimeType(MimeTypes.APPLICATION_MPD)
                }
                clean.endsWith(".ism") -> {
                    builder.setMimeType(MimeTypes.APPLICATION_SS)
                }
                clean.endsWith(".mp4") -> {
                    builder.setMimeType(MimeTypes.VIDEO_MP4)
                }
                clean.endsWith(".mkv") -> {
                    builder.setMimeType(MimeTypes.VIDEO_MATROSKA)
                }
                clean.endsWith(".webm") -> {
                    builder.setMimeType(MimeTypes.VIDEO_WEBM)
                }
            }
        }
        return builder.build()
    }

    private fun sourceUri(url: String): Uri {
        return when {
            url.startsWith("file://") -> Uri.parse(url)
            url.startsWith("/") -> Uri.fromFile(File(url))
            else -> Uri.parse(url)
        }
    }

    override fun onRenderedFirstFrame() {
        channel.invokeMethod("onRenderedFirstFrame", null)
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        channel.invokeMethod(
            "onStateChanged",
            mapOf(
                "playWhenReady" to player.playWhenReady,
                "playbackState" to playbackState,
                "isPlaying" to player.isPlaying
            )
        )
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        channel.invokeMethod("onIsPlayingChanged", isPlaying)
        channel.invokeMethod(
            "onStateChanged",
            mapOf(
                "playWhenReady" to player.playWhenReady,
                "playbackState" to player.playbackState,
                "isPlaying" to isPlaying
            )
        )
    }

    override fun onPlayerStateChanged(playWhenReady: Boolean, playbackState: Int) {
        channel.invokeMethod(
            "onStateChanged",
            mapOf(
                "playWhenReady" to playWhenReady,
                "playbackState" to playbackState,
                "isPlaying" to player.isPlaying
            )
        )
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int
    ) {
        channel.invokeMethod("onPositionDiscontinuity", mapOf("reason" to reason))
    }

    override fun onTimelineChanged(timeline: Timeline, reason: Int) {
        channel.invokeMethod("onTimelineChanged", mapOf("reason" to reason))
    }

    override fun onTracksChanged(tracks: Tracks) {
        channel.invokeMethod("onTracksChanged", null)
    }

    override fun onLoadingChanged(isLoading: Boolean) {
        channel.invokeMethod("onLoadingChanged", isLoading)
    }

    override fun onPlayerError(error: PlaybackException) {
        channel.invokeMethod("onPlayerError", error.message ?: "unknown_error")
    }

    private fun release() {
        if (released) return
        released = true
        player.removeListener(this)
        player.release()
        channel.setMethodCallHandler(null)
    }

    override fun dispose() {
        release()
    }
}

class ExoPlayerPlatformViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<Any, Any>()
        val channelName = params["channelName"] as? String
            ?: "com.yeflix.app/exoplayer_$viewId"
        return ExoPlayerPlatformView(context, viewId, messenger, channelName)
    }
}
