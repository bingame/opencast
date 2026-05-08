package com.opencast.app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.opencast.app.MainActivity
import com.opencast.app.R
import com.opencast.app.webrtc.WebRTCClient
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * 屏幕采集前台服务
 *
 * Android 14+ 要求屏幕采集必须在带有 mediaProjection 类型的前台服务中进行。
 * 该服务负责：
 * - 管理屏幕采集的生命周期
 * - 显示通知栏投屏状态
 * - 提供 Binder 接口供 Activity 控制投屏
 *
 * @property webRTCClient WebRTC 客户端（由 Hilt 注入）
 */
@AndroidEntryPoint
class ScreenCaptureService : Service() {

    companion object {
        private const val TAG = "ScreenCaptureService"

        /** 通知渠道 ID */
        private const val CHANNEL_ID = "opencast_screen_capture"

        /** 通知 ID */
        private const val NOTIFICATION_ID = 1001

        /** 投屏状态 Action */
        const val ACTION_START_CASTING = "com.opencast.app.action.START_CASTING"
        const val ACTION_STOP_CASTING = "com.opencast.app.action.STOP_CASTING"

        /** Intent Extra 键 */
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_DATA = "data"
        const val EXTRA_TARGET_DEVICE_ID = "target_device_id"
        const val EXTRA_SIGNALING_URL = "signaling_url"

        /**
         * 创建投屏通知渠道
         */
        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = context.getString(R.string.notification_channel_description)
                    setShowBadge(false)
                }

                val notificationManager = context.getSystemService(
                    NotificationManager::class.java
                )
                notificationManager.createNotificationChannel(channel)
            }
        }

        /**
         * 创建启动服务的 Intent
         */
        fun createStartIntent(
            context: Context,
            resultCode: Int,
            data: Intent,
            targetDeviceId: String,
            signalingUrl: String
        ): Intent {
            return Intent(context, ScreenCaptureService::class.java).apply {
                action = ACTION_START_CASTING
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_DATA, data)
                putExtra(EXTRA_TARGET_DEVICE_ID, targetDeviceId)
                putExtra(EXTRA_SIGNALING_URL, signalingUrl)
            }
        }

        /**
         * 创建停止服务的 Intent
         */
        fun createStopIntent(context: Context): Intent {
            return Intent(context, ScreenCaptureService::class.java).apply {
                action = ACTION_STOP_CASTING
            }
        }
    }

    @Inject
    lateinit var webRTCClient: WebRTCClient

    /** 服务 Binder */
    private val binder = LocalBinder()

    /** MediaProjection */
    private var mediaProjection: MediaProjection? = null

    /** 是否正在投屏 */
    private var isCasting = false

    /** 目标设备 ID */
    private var targetDeviceId: String = ""

    /**
     * 本地 Binder，提供对 Service 实例的访问
     */
    inner class LocalBinder : Binder() {
        fun getService(): ScreenCaptureService = this@ScreenCaptureService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "屏幕采集服务已创建")
        createNotificationChannel(this)
    }

    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "绑定屏幕采集服务")
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_CASTING -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_DATA)
                }
                targetDeviceId = intent.getStringExtra(EXTRA_TARGET_DEVICE_ID) ?: ""
                val signalingUrl = intent.getStringExtra(EXTRA_SIGNALING_URL) ?: ""

                startScreenCapture(resultCode, data, signalingUrl)
            }
            ACTION_STOP_CASTING -> {
                stopScreenCapture()
            }
        }

        return START_NOT_STICKY
    }

    /**
     * 开始屏幕采集
     *
     * @param resultCode MediaProjection 授权结果码
     * @param data MediaProjection 授权数据
     * @param signalingUrl 信令服务器地址
     */
    private fun startScreenCapture(
        resultCode: Int,
        data: Intent?,
        signalingUrl: String
    ) {
        if (data == null) {
            Log.e(TAG, "MediaProjection 数据为空")
            stopSelf()
            return
        }

        try {
            // 启动前台服务并显示通知
            startForeground(NOTIFICATION_ID, createCastingNotification())

            // 获取 MediaProjection
            val mediaProjectionManager = getSystemService(
                Context.MEDIA_PROJECTION_SERVICE
            ) as MediaProjectionManager
            mediaProjection = mediaProjectionManager.getMediaProjection(resultCode, data)

            if (mediaProjection == null) {
                Log.e(TAG, "获取 MediaProjection 失败")
                stopSelf()
                return
            }

            // 初始化 WebRTC
            val initialized = webRTCClient.initialize()
            if (!initialized) {
                Log.e(TAG, "WebRTC 初始化失败")
                stopSelf()
                return
            }

            // 连接信令服务器
            webRTCClient.signalingClient.connect(signalingUrl)

            // 开始投屏
            webRTCClient.startCasting(
                mediaProjection!!,
                resultCode,
                data,
                targetDeviceId
            )

            isCasting = true
            updateNotification("正在投屏", "已连接到 $targetDeviceId")

            Log.d(TAG, "屏幕采集已启动")

        } catch (e: Exception) {
            Log.e(TAG, "启动屏幕采集失败", e)
            stopSelf()
        }
    }

    /**
     * 停止屏幕采集
     */
    private fun stopScreenCapture() {
        try {
            webRTCClient.stopCasting()
            webRTCClient.signalingClient.disconnect()
            mediaProjection?.stop()
            mediaProjection = null
            isCasting = false

            // 停止前台服务
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()

            Log.d(TAG, "屏幕采集已停止")
        } catch (e: Exception) {
            Log.e(TAG, "停止屏幕采集失败", e)
        }
    }

    /**
     * 创建投屏通知
     */
    private fun createCastingNotification(): Notification {
        // 点击通知打开应用
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 停止投屏按钮
        val stopIntent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ACTION_STOP_CASTING
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text))
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.notification_stop),
                stopPendingIntent
            )
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    /**
     * 更新通知内容
     */
    private fun updateNotification(title: String, text: String) {
        val notificationManager = getSystemService(
            NotificationManager::class.java
        )
        val notification = createCastingNotification().apply {
            val openIntent = Intent(this@ScreenCaptureService, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openPendingIntent = PendingIntent.getActivity(
                this@ScreenCaptureService, 0, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val stopIntent = Intent(this@ScreenCaptureService, ScreenCaptureService::class.java).apply {
                action = ACTION_STOP_CASTING
            }
            val stopPendingIntent = PendingIntent.getService(
                this@ScreenCaptureService, 1, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            NotificationCompat.Builder(this@ScreenCaptureService, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(R.drawable.ic_launcher_foreground)
                .setContentIntent(openPendingIntent)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    getString(R.string.notification_stop),
                    stopPendingIntent
                )
                .setOngoing(true)
                .setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
        }
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    /**
     * 是否正在投屏
     */
    fun isCasting(): Boolean = isCasting

    override fun onDestroy() {
        stopScreenCapture()
        super.onDestroy()
        Log.d(TAG, "屏幕采集服务已销毁")
    }
}
