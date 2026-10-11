package com.b1g.b1gtv

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

/**
 * The second player engine: Google's ExoPlayer (Media3), drawing with the TV's own
 * video chip. Flutter opens it with the channel list, the start channel and (for
 * films) the start position; it hands back the last channel and position on exit.
 *
 * Live: Up / Down (or Channel +/-) change the channel while the controls are hidden.
 * Each channel can carry several addresses (ts / m3u8); a failing one moves to the next.
 */
class ExoActivity : Activity() {

    companion object {
        const val EXTRA_TITLES = "titles"
        const val EXTRA_URLS = "urls"          // one entry per channel: addresses joined by '\n'
        const val EXTRA_INDEX = "index"
        const val EXTRA_LIVE = "live"
        const val EXTRA_START_MS = "startMs"
        const val EXTRA_UA = "ua"
        const val RESULT_INDEX = "index"
        const val RESULT_POSITION_MS = "positionMs"
        const val RESULT_DURATION_MS = "durationMs"
    }

    private lateinit var player: ExoPlayer
    private lateinit var view: PlayerView
    private lateinit var label: TextView
    private val ui = Handler(Looper.getMainLooper())

    private var titles: List<String> = emptyList()
    private var urls: List<List<String>> = emptyList()
    private var index = 0
    private var urlIndex = 0
    private var live = true
    private var lastPosition = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)

        titles = intent.getStringArrayListExtra(EXTRA_TITLES) ?: arrayListOf()
        urls = (intent.getStringArrayListExtra(EXTRA_URLS) ?: arrayListOf())
            .map { s -> s.split('\n').map { it.trim() }.filter { it.isNotEmpty() } }
        index = intent.getIntExtra(EXTRA_INDEX, 0).coerceIn(0, maxOf(0, urls.size - 1))
        live = intent.getBooleanExtra(EXTRA_LIVE, true)
        val startMs = intent.getLongExtra(EXTRA_START_MS, 0L)
        val ua = intent.getStringExtra(EXTRA_UA) ?: "CloudPlayer/1.0 (Android TV)"

        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(ua)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(20000)
        // Start fast (1.5 s of video is enough to begin), keep up to 50 s in reserve.
        val load = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15000, 50000, 1500, 3000)
            .build()
        val renderers = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
        player = ExoPlayer.Builder(this, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(http))
            .setLoadControl(load)
            .build()

        view = PlayerView(this).apply {
            this.player = this@ExoActivity.player
            useController = true
            controllerShowTimeoutMs = 3500
            setShowNextButton(false)
            setShowPreviousButton(false)
            keepScreenOn = true
            setBackgroundColor(Color.BLACK)
        }
        label = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 22f
            setShadowLayer(8f, 0f, 2f, Color.BLACK)
            setPadding(48, 32, 48, 32)
            visibility = View.GONE
        }
        val root = FrameLayout(this)
        root.addView(view, FrameLayout.LayoutParams(-1, -1))
        root.addView(label, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.START))
        setContentView(root)

        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                // A dropped live stream (behind the live window) simply restarts at the live edge.
                if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
                    player.seekToDefaultPosition()
                    player.prepare()
                    return
                }
                val list = urls.getOrNull(index) ?: emptyList()
                if (urlIndex + 1 < list.size) {
                    urlIndex++
                    play(keepPosition = true)
                } else {
                    showLabel("${titles.getOrNull(index) ?: ""}\nNot available in ExoPlayer right now.", 6000)
                }
            }
        })

        play(startAt = startMs)
    }

    private fun play(startAt: Long = 0L, keepPosition: Boolean = false) {
        val list = urls.getOrNull(index) ?: return
        val url = list.getOrNull(urlIndex) ?: return
        val pos = if (keepPosition && !live) player.currentPosition else startAt
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
        if (!live && pos > 0) player.seekTo(pos)
        player.playWhenReady = true
        showLabel(titles.getOrNull(index) ?: "", 3000)
    }

    private fun zap(step: Int) {
        if (urls.isEmpty()) return
        index = (index + step + urls.size) % urls.size
        urlIndex = 0
        play()
    }

    private fun showLabel(text: String, ms: Long) {
        if (text.isBlank()) return
        label.text = text
        label.visibility = View.VISIBLE
        ui.removeCallbacksAndMessages(null)
        ui.postDelayed({ label.visibility = View.GONE }, ms)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (live && event.action == KeyEvent.ACTION_DOWN && !view.isControllerFullyVisible) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_CHANNEL_UP -> { zap(-1); return true }
                KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> { zap(1); return true }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onBackPressed() {
        if (view.isControllerFullyVisible) {
            view.hideController()
            return
        }
        finishWithResult()
    }

    private fun finishWithResult() {
        lastPosition = if (player.currentPosition > 0) player.currentPosition else lastPosition
        val duration = player.duration.let { if (it == C.TIME_UNSET) 0L else it }
        setResult(RESULT_OK, Intent()
            .putExtra(RESULT_INDEX, index)
            .putExtra(RESULT_POSITION_MS, lastPosition)
            .putExtra(RESULT_DURATION_MS, duration))
        finish()
    }

    override fun onStop() {
        super.onStop()
        lastPosition = player.currentPosition
        player.pause()
    }

    override fun onStart() {
        super.onStart()
        if (::player.isInitialized && player.playbackState != Player.STATE_IDLE) player.playWhenReady = true
    }

    override fun onDestroy() {
        ui.removeCallbacksAndMessages(null)
        player.release()
        super.onDestroy()
    }
}
