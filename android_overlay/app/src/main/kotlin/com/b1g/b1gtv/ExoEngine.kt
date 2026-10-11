package com.b1g.b1gtv

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * ExoPlayer (Media3) as a player engine inside the Flutter screen.
 *
 * The picture is drawn into a Flutter texture, so the app's own controls (channel list, audio,
 * subtitles, quality, EPG...) stay on top of it. Flutter talks to it over the "b1g/exo" channel:
 * create / open / play / pause / seek / rate / track / dispose / facts. Changes come back as
 * "event" calls with the engine id: state (position, duration, buffering, playing), size,
 * tracks, cues (subtitle text), ended and error.
 */
class ExoEngine(
    private val context: Context,
    private val textures: TextureRegistry,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "b1g/exo")
    private val sessions = HashMap<Int, Session>()
    private var nextId = 1
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun disposeAll() {
        sessions.values.forEach { it.release() }
        sessions.clear()
    }

    private fun send(id: Int, type: String, data: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>(data)
        payload["id"] = id
        payload["type"] = type
        main.post {
            try {
                channel.invokeMethod("event", payload)
            } catch (_: Exception) {
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "create") {
                val id = nextId++
                val live = call.argument<Boolean>("live") ?: true
                val ua = call.argument<String>("ua") ?: "CloudPlayer/1.0 (Android TV)"
                val s = Session(id, live, ua)
                sessions[id] = s
                result.success(mapOf("id" to id, "texture" to s.textureId))
                return
            }
            val id = (call.argument<Number>("id") ?: 0).toInt()
            val s = sessions[id]
            if (s == null) {
                result.success(null)
                return
            }
            when (call.method) {
                "open" -> s.open(call.argument<String>("url") ?: "", (call.argument<Number>("startMs") ?: 0).toLong())
                "play" -> s.player.play()
                "pause" -> s.player.pause()
                "seek" -> s.player.seekTo((call.argument<Number>("ms") ?: 0).toLong())
                "rate" -> s.player.playbackParameters = PlaybackParameters((call.argument<Number>("rate") ?: 1.0).toFloat())
                "track" -> s.selectTrack(call.argument<String>("kind") ?: "", call.argument<String>("track") ?: "")
                "facts" -> {
                    result.success(s.facts())
                    return
                }
                "dispose" -> {
                    s.release()
                    sessions.remove(id)
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("exo", e.message, null)
        }
    }

    private inner class Session(val id: Int, private val live: Boolean, ua: String) {
        private val producer: TextureRegistry.SurfaceProducer = textures.createSurfaceProducer()
        val textureId: Long = producer.id()
        val player: ExoPlayer
        private var released = false
        private var tracks: Tracks = Tracks.EMPTY
        private var decoder = ""
        private var dropped = 0
        private val ticker = object : Runnable {
            override fun run() {
                if (released) return
                sendState()
                main.postDelayed(this, 250)
            }
        }

        init {
            val http = DefaultHttpDataSource.Factory()
                .setUserAgent(ua)
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(20000)
            // Live: start after 1.5 s of video and keep up to 30 s; films keep up to 60 s.
            val load = DefaultLoadControl.Builder()
                .setBufferDurationsMs(if (live) 10000 else 20000, if (live) 30000 else 60000, 1500, 3000)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()
            val renderers = DefaultRenderersFactory(context)
                .setEnableDecoderFallback(true)
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
            player = ExoPlayer.Builder(context, renderers)
                .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http)))
                .setLoadControl(load)
                .build()

            producer.setSize(1920, 1080)
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    if (!released) player.setVideoSurface(producer.surface)
                }

                override fun onSurfaceCleanup() {
                    if (!released) player.setVideoSurface(null)
                }
            })
            player.setVideoSurface(producer.surface)

            player.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) {
                    sendState()
                    if (state == Player.STATE_ENDED) send(id, "ended")
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) = sendState()

                override fun onPlayerError(error: PlaybackException) {
                    // A live stream that fell behind simply restarts at the live edge.
                    if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                        player.seekToDefaultPosition()
                        player.prepare()
                        return
                    }
                    send(id, "error", mapOf("message" to "${error.errorCodeName}: ${error.message ?: ""}"))
                }

                override fun onVideoSizeChanged(size: VideoSize) {
                    if (size.width <= 0 || size.height <= 0) return
                    producer.setSize(size.width, size.height)
                    player.setVideoSurface(producer.surface)
                    send(id, "size", mapOf("w" to size.width, "h" to size.height))
                }

                override fun onTracksChanged(t: Tracks) {
                    tracks = t
                    send(id, "tracks", mapOf("list" to describeTracks(t)))
                }

                override fun onCues(cueGroup: CueGroup) {
                    val text = cueGroup.cues.mapNotNull { it.text?.toString() }.joinToString("\n")
                    send(id, "cues", mapOf("text" to text))
                }
            })
            player.addAnalyticsListener(object : AnalyticsListener {
                override fun onVideoDecoderInitialized(
                    eventTime: AnalyticsListener.EventTime,
                    decoderName: String,
                    initializedTimestampMs: Long,
                    initializationDurationMs: Long,
                ) {
                    decoder = decoderName
                }

                override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
                    dropped += droppedFrames
                }
            })
            main.post(ticker)
        }

        fun open(url: String, startMs: Long) {
            player.setMediaItem(MediaItem.fromUri(url), if (!live && startMs > 0) startMs else C.TIME_UNSET)
            player.prepare()
            player.playWhenReady = true
        }

        private fun sendState() {
            if (released) return
            val dur = player.duration
            send(id, "state", mapOf(
                "pos" to player.currentPosition,
                "dur" to (if (dur == C.TIME_UNSET || dur < 0) 0L else dur),
                "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                "playing" to player.isPlaying,
                "idle" to (player.playbackState == Player.STATE_IDLE),
            ))
        }

        private fun describeTracks(t: Tracks): List<Map<String, Any?>> {
            val list = ArrayList<Map<String, Any?>>()
            t.groups.forEachIndexed { g, group ->
                val kind = when (group.type) {
                    C.TRACK_TYPE_AUDIO -> "a"
                    C.TRACK_TYPE_TEXT -> "s"
                    C.TRACK_TYPE_VIDEO -> "v"
                    else -> return@forEachIndexed
                }
                for (i in 0 until group.length) {
                    if (!group.isTrackSupported(i, true)) continue
                    val f = group.getTrackFormat(i)
                    list.add(mapOf(
                        "kind" to kind,
                        "id" to "$kind:$g:$i",
                        "language" to f.language,
                        "label" to f.label,
                        "w" to (if (f.width > 0) f.width else null),
                        "h" to (if (f.height > 0) f.height else null),
                        "bitrate" to (if (f.bitrate > 0) f.bitrate else null),
                        "selected" to group.isTrackSelected(i),
                    ))
                }
            }
            return list
        }

        /** kind: a / s / v; track: "kind:group:index", "no" (subtitles off) or "auto" (best video). */
        fun selectTrack(kind: String, track: String) {
            val type = when (kind) {
                "a" -> C.TRACK_TYPE_AUDIO
                "s" -> C.TRACK_TYPE_TEXT
                "v" -> C.TRACK_TYPE_VIDEO
                else -> return
            }
            val b = player.trackSelectionParameters.buildUpon()
            if (track == "no") {
                b.setTrackTypeDisabled(type, true)
            } else if (track == "auto") {
                b.setTrackTypeDisabled(type, false).clearOverridesOfType(type)
            } else {
                val parts = track.split(':')
                val g = parts.getOrNull(1)?.toIntOrNull() ?: return
                val i = parts.getOrNull(2)?.toIntOrNull() ?: return
                val group = tracks.groups.getOrNull(g) ?: return
                b.setTrackTypeDisabled(type, false)
                    .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
            }
            player.trackSelectionParameters = b.build()
        }

        fun facts(): Map<String, Any?> {
            val v = player.videoFormat
            val a = player.audioFormat
            return mapOf(
                "video" to (v?.sampleMimeType ?: ""),
                "fps" to (v?.frameRate ?: 0f).toDouble(),
                "decoder" to decoder,
                "audio" to (a?.sampleMimeType ?: ""),
                "dropped" to dropped,
            )
        }

        fun release() {
            if (released) return
            released = true
            main.removeCallbacks(ticker)
            try {
                player.release()
            } catch (_: Exception) {
            }
            try {
                producer.release()
            } catch (_: Exception) {
            }
        }
    }
}
