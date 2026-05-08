package com.opencast.app.webrtc

import android.content.Context
import android.media.projection.MediaProjection
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import org.webrtc.*
import java.util.concurrent.ConcurrentHashMap

/**
 * 屏幕采集封装类
 *
 * 使用 MediaProjection API 采集屏幕内容，
 * 并将采集到的视频流传递给 WebRTC VideoCapturer。
 *
 * @param context 应用上下文
 */
class ScreenCapturer(
    private val context: Context
) {
    companion object {
        private const val TAG = "ScreenCapturer"

        /** 视频帧率 */
        private const val VIDEO_FPS = 30

        /** 视频比特率（kbps） */
        private const val VIDEO_BITRATE = 2_500_000
    }

    /** WebRTC 视频采集器 */
    private var videoCapturer: VideoCapturer? = null

    /** 本地视频源 */
    private var localVideoSource: VideoSource? = null

    /** 本地视频轨道 */
    private var localVideoTrack: VideoTrack? = null

    /** 本地音频源 */
    private var localAudioSource: AudioSource? = null

    /** 本地音频轨道 */
    private var localAudioTrack: AudioTrack? = null

    /** 屏幕采集器（用于 Android 10+） */
    private var screenCapturer: org.webrtc.ScreenCapturerAndroid? = null

    /** 是否正在采集 */
    @Volatile
    private var isCapturing = false

    /**
     * 初始化屏幕采集
     *
     * 必须在获取 MediaProjection 授权后调用。
     *
     * @param mediaProjection MediaProjection 授权结果
     * @param resultCode 授权结果码
     * @param data 授权返回的 Intent 数据
     * @param peerConnectionFactory PeerConnectionFactory 实例
     * @return 初始化是否成功
     */
    fun initialize(
        mediaProjection: MediaProjection,
        resultCode: Int,
        data: android.content.Intent,
        peerConnectionFactory: PeerConnectionFactory
    ): Boolean {
        return try {
            // 获取屏幕分辨率
            val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val displayMetrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getMetrics(displayMetrics)
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels

            // 创建视频采集器
            screenCapturer = org.webrtc.ScreenCapturerAndroid(data, object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.d(TAG, "屏幕采集已停止")
                    isCapturing = false
                }
            })

            // 创建视频源
            localVideoSource = peerConnectionFactory.createVideoSource(screenCapturer!!.isScreencast)

            // 初始化采集器
            screenCapturer?.initialize(
                SurfaceTextureHelper.create("CaptureThread", null),
                context,
                localVideoSource?.capturerObserver
            )

            // 创建视频轨道
            localVideoTrack = peerConnectionFactory.createVideoTrack("video_track", localVideoSource)
            localVideoTrack?.setEnabled(true)

            // 创建音频源和轨道（Android 10+ 支持系统音频采集）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                localAudioSource = peerConnectionFactory.createAudioSource(
                    MediaConstraints().apply {
                        // 音频约束
                        mandatory.add(MediaConstraints.KeyValuePair("googEchoCancellation", "true"))
                        mandatory.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "true"))
                        mandatory.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
                    }
                )
                localAudioTrack = peerConnectionFactory.createAudioTrack("audio_track", localAudioSource)
                localAudioTrack?.setEnabled(true)
            }

            isCapturing = true
            Log.d(TAG, "屏幕采集初始化成功: ${screenWidth}x${screenHeight}")
            true

        } catch (e: Exception) {
            Log.e(TAG, "屏幕采集初始化失败", e)
            false
        }
    }

    /**
     * 开始采集屏幕
     *
     * @param width 视频宽度
     * @param height 视频高度
     * @param fps 帧率
     */
    fun startCapture(width: Int = 0, height: Int = 0, fps: Int = VIDEO_FPS) {
        if (!isCapturing) {
            Log.w(TAG, "屏幕采集未初始化，无法开始采集")
            return
        }

        try {
            val captureWidth = if (width > 0) width else getScreenWidth()
            val captureHeight = if (height > 0) height else getScreenHeight()

            screenCapturer?.startCapture(captureHeight, captureWidth, fps)
            Log.d(TAG, "开始屏幕采集: ${captureWidth}x${captureHeight}@$fps fps")
        } catch (e: Exception) {
            Log.e(TAG, "开始屏幕采集失败", e)
        }
    }

    /**
     * 停止采集屏幕
     */
    fun stopCapture() {
        try {
            screenCapturer?.stopCapture()
            isCapturing = false
            Log.d(TAG, "屏幕采集已停止")
        } catch (e: Exception) {
            Log.e(TAG, "停止屏幕采集失败", e)
        }
    }

    /**
     * 获取本地视频轨道
     */
    fun getVideoTrack(): VideoTrack? = localVideoTrack

    /**
     * 获取本地音频轨道
     */
    fun getAudioTrack(): AudioTrack? = localAudioTrack

    /**
     * 获取屏幕宽度
     */
    fun getScreenWidth(): Int {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getMetrics(displayMetrics)
        return displayMetrics.widthPixels
    }

    /**
     * 获取屏幕高度
     */
    fun getScreenHeight(): Int {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getMetrics(displayMetrics)
        return displayMetrics.heightPixels
    }

    /**
     * 是否正在采集
     */
    fun isCapturing(): Boolean = isCapturing

    /**
     * 释放所有资源
     */
    fun dispose() {
        stopCapture()
        localVideoTrack?.dispose()
        localAudioTrack?.dispose()
        localVideoSource?.dispose()
        localAudioSource?.dispose()
        screenCapturer?.dispose()

        localVideoTrack = null
        localAudioTrack = null
        localVideoSource = null
        localAudioSource = null
        screenCapturer = null
        isCapturing = false

        Log.d(TAG, "屏幕采集资源已释放")
    }
}
