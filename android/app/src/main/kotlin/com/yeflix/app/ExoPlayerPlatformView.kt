package com.yeflix.app

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
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
        // Si el reproductor se reinicia o se re-prepara, conserva el ultimo
        // fotograma en pantalla en lugar de dejar el surface en negro.
        setKeepContentOnPlayerReset(true)
    }

    /**
     * Selector de pistas con limites opcionales. Para VidHide se limita a
     * 720p porque su CDN entrega ~400 KB/s por conexion: un segmento 1080p de
     * 10 s tarda 8-11 s en bajar y el buffer acaba vaciandose. En 720p el
     * mismo segmento baja en 3.5-7 s y el buffer crece.
     *
     * `setExceedVideoConstraintsIfNecessary(true)` evita dejar sin video una
     * playlist que solo trae una variante superior al limite (por ejemplo al
     * cambiar de calidad manualmente).
     */
    private val trackSelector = DefaultTrackSelector(context)

    private val player = ExoPlayer.Builder(context)
        .setTrackSelector(trackSelector)
        .setLoadControl(
            DefaultLoadControl.Builder()
                // 20s/50s de buffer en segundo plano. El umbral para empezar a
                // reproducir baja de 2.5s a 1.5s: el primer fotograma aparece
                // antes sin reducir el colchón total (el buffer sigue
                // llenándose mientras se reproduce). Tras un rebuffer se
                // mantienen 4s para no encadenar cortes en CDNs lentos.
                .setBufferDurationsMs(20_000, 50_000, 1_500, 4_000)
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

    companion object {
        /**
         * Ultima instancia viva por nombre de canal.
         *
         * Durante una recreacion de la PlatformView pueden coexistir dos
         * instancias con el mismo canal. Si la vieja se libera despues de que
         * la nueva registro su handler y llamara a
         * `setMethodCallHandler(null)`, dejaria al reproductor nuevo sin canal:
         * `setSource` fallaria y el video nunca arrancaria (pantalla vacia).
         * Solo la instancia mas reciente puede limpiar el handler.
         *
         * Se accede unicamente desde el hilo de plataforma (creacion/liberacion
         * de PlatformView), por eso no hace falta sincronizar.
         */
        private val latestByChannel =
            mutableMapOf<String, ExoPlayerPlatformView>()
    }

    /**
     * Fuente aplicada actualmente. Se usa para ignorar llamadas `setSource`
     * duplicadas que llegan cuando Flutter reconstruye la vista (abrir el
     * panel de subtítulos, rotar la pantalla, mostrar un mensaje...).
     *
     * Re-preparar la misma fuente reinicia el video en 0, vacía el buffer y
     * vuelve a descargar el playlist: era la causa de que el loader apareciera
     * y el video empezara de nuevo.
     */
    private var currentSourceUrl: String? = null
    private var currentHeaders: Map<String, String> = emptyMap()
    private var currentMimeType: String? = null
    private var currentMaxVideoHeight = 0
    private var currentMaxVideoBitrate = 0

    // Mantiene la pantalla encendida mientras el video se está reproduciendo.
    // El contexto de una PlatformView es el de la Activity, pero se recorre la
    // cadena de ContextWrapper por si Flutter entrega un contexto envoltorio.
    private val hostActivity: Activity? = findActivity(context)
    private var keepScreenOn = false

    private fun findActivity(ctx: Context): Activity? {
        var current: Context? = ctx
        while (current is ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return current as? Activity
    }

    /**
     * Activa o desactiva FLAG_KEEP_SCREEN_ON en la ventana de la Activity.
     *
     * Se usa el flag de ventana (y no solo `View.keepScreenOn`) porque la vista
     * del reproductor se dibuja dentro de una PlatformView de Flutter y su flag
     * no siempre llega a la ventana. Con el flag en la ventana el sistema no
     * apaga la pantalla por inactividad mientras se reproduce el video.
     */
    private fun setKeepScreenOn(enabled: Boolean) {
        if (keepScreenOn == enabled) return
        keepScreenOn = enabled
        playerView.keepScreenOn = enabled
        container.keepScreenOn = enabled
        val activity = hostActivity ?: return
        activity.runOnUiThread {
            if (enabled) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    /**
     * Decide si la pantalla debe permanecer encendida: sí mientras el usuario
     * quiere reproducir (playWhenReady) y el reproductor está listo o cargando.
     * Al pausar, al terminar o al cerrar el reproductor se libera el flag.
     */
    private fun updateKeepScreenOn() {
        val state = player.playbackState
        val active = player.playWhenReady &&
            (state == Player.STATE_READY || state == Player.STATE_BUFFERING)
        setKeepScreenOn(active)
    }

    init {
        playerView.player = player
        latestByChannel[channelName] = this
        channel.setMethodCallHandler(this)
        // Avisa a Flutter de que esta instancia nativa esta lista. Si la vista
        // se recrea (rotacion, cambio de layout, vuelta desde segundo plano),
        // el controlador reabre la misma fuente en la ultima posicion conocida
        // en vez de empezar de cero.
        channel.invokeMethod("onViewAttached", null)
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSource" -> {
                val url = call.argument<String>("url") ?: ""
                val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                val positionMs = call.argument<Int>("positionMs") ?: 0
                val mimeType = call.argument<String>("mimeType")
                val maxVideoHeight = call.argument<Int>("maxVideoHeight") ?: 0
                val maxVideoBitrate = call.argument<Int>("maxVideoBitrate") ?: 0
                if (url.isBlank()) {
                    result.error("no_url", "URL de origen vacía", null)
                    return
                }

                // Idempotencia: si ya es la misma fuente y sigue activa, no se
                // vuelve a preparar. Solo se hace seek si se pidió una posición
                // distinta de la actual.
                //
                // Los límites y el mime son opcionales: un valor 0/vacío
                // significa "no especificado" y no invalida la comparación.
                // Antes se comparaban de forma estricta y cualquier llamada
                // repetida sin los límites (por ejemplo desde un rebuild de la
                // UI) se trataba como fuente nueva y reiniciaba el video.
                val sameSource = url == currentSourceUrl &&
                    (maxVideoHeight == 0 || maxVideoHeight == currentMaxVideoHeight) &&
                    (maxVideoBitrate == 0 || maxVideoBitrate == currentMaxVideoBitrate) &&
                    (mimeType.isNullOrBlank() || mimeType == currentMimeType) &&
                    (headers.isEmpty() || headers == currentHeaders)
                val sameSourceActive = sameSource &&
                    player.playerError == null &&
                    (player.playbackState == Player.STATE_READY ||
                        player.playbackState == Player.STATE_BUFFERING)
                if (sameSourceActive) {
                    if (positionMs > 0 &&
                        kotlin.math.abs(player.currentPosition - positionMs) > 1_000
                    ) {
                        player.seekTo(positionMs.toLong())
                    }
                    result.success(null)
                    return
                }

                currentSourceUrl = url
                currentHeaders = headers
                currentMimeType = mimeType
                currentMaxVideoHeight = maxVideoHeight
                currentMaxVideoBitrate = maxVideoBitrate

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

                    applyTrackLimits(maxVideoHeight, maxVideoBitrate)

                    val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
                    val mediaItem = buildMediaItem(url, mimeType)
                    val mediaSource = DefaultMediaSourceFactory(dataSourceFactory)
                        .setLoadErrorHandlingPolicy(YeflixLoadErrorPolicy())
                        .createMediaSource(mediaItem)

                    player.setMediaSource(mediaSource)
                    if (positionMs > 0) {
                        player.seekTo(positionMs.toLong())
                    }
                    player.prepare()
                    player.playWhenReady = true
                    updateKeepScreenOn()
                    result.success(null)
                } catch (t: Throwable) {
                    val msg = t.message ?: t.javaClass.simpleName
                    channel.invokeMethod("onPlayerError", "Error al inicializar reproductor: $msg")
                    result.error("init_error", msg, null)
                }
            }
            "play" -> {
                player.playWhenReady = true
                updateKeepScreenOn()
                result.success(null)
            }
            "pause" -> {
                player.playWhenReady = false
                setKeepScreenOn(false)
                result.success(null)
            }
            "seek" -> {
                val positionMs = call.argument<Int>("positionMs") ?: 0
                player.seekTo(positionMs.toLong())
                result.success(null)
            }
            "recover" -> {
                val positionMs = call.argument<Int>("positionMs")
                    ?: player.currentPosition.toInt()
                try {
                    if (player.playerError != null ||
                        player.playbackState == Player.STATE_IDLE
                    ) {
                        // prepare() vuelve a intentar desde la ultima posicion
                        // conocida; el error se limpia solo.
                        player.prepare()
                    } else {
                        // Un seek al mismo punto cancela la carga colgada y
                        // vuelve a pedir el segmento actual.
                        player.seekTo(positionMs.toLong())
                    }
                    player.playWhenReady = true
                    updateKeepScreenOn()
                    result.success(null)
                } catch (t: Throwable) {
                    result.error(
                        "recover_error",
                        t.message ?: t.javaClass.simpleName,
                        null
                    )
                }
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                player.setVolume(volume.toFloat())
                result.success(null)
            }
            "setSubtitlesEnabled" -> {
                // Cuando Yeflix dibuja un subtítulo externo en Flutter se
                // desactivan las pistas de texto nativas para no duplicar.
                val enabled = call.argument<Boolean>("enabled") ?: true
                val builder = trackSelector.buildUponParameters()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !enabled)
                if (enabled) {
                    builder.clearOverridesOfType(C.TRACK_TYPE_TEXT)
                }
                trackSelector.setParameters(builder)
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

    /**
     * Aplica (o limpia) el limite de calidad. Un valor 0 significa "sin
     * limite": asi el menu de calidades puede abrir 1080p manualmente.
     */
    private fun applyTrackLimits(maxVideoHeight: Int, maxVideoBitrate: Int) {
        val builder = trackSelector.buildUponParameters()
        if (maxVideoHeight > 0) {
            builder.setMaxVideoSize(Int.MAX_VALUE, maxVideoHeight)
        } else {
            builder.clearVideoSizeConstraints()
        }
        if (maxVideoBitrate > 0) {
            builder.setMaxVideoBitrate(maxVideoBitrate)
        } else {
            builder.setMaxVideoBitrate(Int.MAX_VALUE)
        }
        builder.setExceedVideoConstraintsIfNecessary(true)
        trackSelector.setParameters(builder)
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
        updateKeepScreenOn()
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
        updateKeepScreenOn()
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
        updateKeepScreenOn()
        channel.invokeMethod(
            "onStateChanged",
            mapOf(
                "playWhenReady" to playWhenReady,
                "playbackState" to playbackState,
                "isPlaying" to player.isPlaying
            )
        )
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        // Cubre pausar/reanudar sin cambio de estado de reproducción.
        updateKeepScreenOn()
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
        currentSourceUrl = null
        currentHeaders = emptyMap()
        currentMimeType = null
        currentMaxVideoHeight = 0
        currentMaxVideoBitrate = 0
        setKeepScreenOn(false)
        player.removeListener(this)
        player.release()
        // Solo la instancia mas reciente puede limpiar el handler: una vista
        // vieja liberada tarde no debe dejar sin canal a la vista nueva.
        if (latestByChannel[channelName] === this) {
            latestByChannel.remove(channelName)
            channel.setMethodCallHandler(null)
        }
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

/**
 * Politica de reintentos para cortes temporales del CDN.
 *
 * El comportamiento por defecto de Media3 reintenta 3 veces con esperas muy
 * cortas. Aqui se reintentan errores de red/5xx/429 con backoff progresivo
 * (1 s, 2 s, 4 s, 4 s, 4 s) y se falla rapido ante 403/404/410, que no se
 * arreglan reintentando (token caducado o fichero eliminado).
 */
private class YeflixLoadErrorPolicy(
    private val maxRetries: Int = 5
) : DefaultLoadErrorHandlingPolicy(maxRetries) {

    override fun getRetryDelayMsFor(
        loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo
    ): Long {
        val code = (loadErrorInfo.exception as?
            HttpDataSource.InvalidResponseCodeException)?.responseCode
        if (code == 403 || code == 404 || code == 410) return C.TIME_UNSET
        if (code != null && code in 400..499 && code != 408 && code != 429) {
            return C.TIME_UNSET
        }
        val shift = (loadErrorInfo.errorCount - 1).coerceIn(0, 2)
        return (1000L shl shift).coerceAtMost(4_000L)
    }

    override fun getMinimumLoadableRetryCount(dataType: Int): Int = maxRetries
}
