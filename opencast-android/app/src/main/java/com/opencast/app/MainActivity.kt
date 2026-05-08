package com.opencast.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.opencast.app.discovery.DiscoveredDevice
import com.opencast.app.service.ScreenCaptureService
import com.opencast.app.ui.screen.CastingScreen
import com.opencast.app.ui.screen.HomeScreen
import com.opencast.app.ui.theme.OpenCastTheme
import com.opencast.app.ui.viewmodel.CastingViewModel
import com.opencast.app.ui.viewmodel.DeviceViewModel
import dagger.hilt.android.AndroidEntryPoint

/**
 * OpenCast 主 Activity
 *
 * 负责管理应用的导航和权限请求。
 * 包含两个主要界面：
 * - HomeScreen: 设备发现和选择
 * - CastingScreen: 投屏状态和控制
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    /** MediaProjection 授权结果码 */
    private var mediaProjectionResultCode: Int = 0

    /** MediaProjection 授权数据 */
    private var mediaProjectionData: Intent? = null

    /** 当前选中的目标设备 */
    private var pendingDevice: DiscoveredDevice? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 创建通知渠道
        ScreenCaptureService.createNotificationChannel(this)

        setContent {
            OpenCastTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    OpenCastNavHost(
                        context = this,
                        onDeviceSelected = { device ->
                            pendingDevice = device
                            requestMediaProjection()
                        },
                        onStopCasting = {
                            stopCastingService()
                        }
                    )
                }
            }
        }
    }

    /**
     * 请求 MediaProjection 授权
     */
    private fun requestMediaProjection() {
        val mediaProjectionManager = getSystemService(
            Context.MEDIA_PROJECTION_SERVICE
        ) as MediaProjectionManager

        val intent = mediaProjectionManager.createScreenCaptureIntent()
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_MEDIA_PROJECTION)
    }

    @Deprecated("使用 Activity Result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == RESULT_OK && data != null) {
                mediaProjectionResultCode = resultCode
                mediaProjectionData = data
                startCastingService()
            } else {
                Toast.makeText(this, "屏幕采集权限被拒绝", Toast.LENGTH_SHORT).show()
                pendingDevice = null
            }
        }
    }

    /**
     * 启动投屏服务
     */
    private fun startCastingService() {
        val device = pendingDevice ?: return
        val data = mediaProjectionData ?: return

        val serviceIntent = ScreenCaptureService.createStartIntent(
            context = this,
            resultCode = mediaProjectionResultCode,
            data = data,
            targetDeviceId = device.deviceId,
            signalingUrl = device.getSignalingUrl()
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        Toast.makeText(this, "开始投屏到 ${device.deviceName}", Toast.LENGTH_SHORT).show()
    }

    /**
     * 停止投屏服务
     */
    private fun stopCastingService() {
        val stopIntent = ScreenCaptureService.createStopIntent(this)
        startService(stopIntent)
        Toast.makeText(this, "投屏已停止", Toast.LENGTH_SHORT).show()
    }

    companion object {
        /** MediaProjection 授权请求码 */
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }
}

/**
 * OpenCast 导航宿主
 *
 * 管理应用内页面导航。
 *
 * @param context Activity 上下文
 * @param onDeviceSelected 设备选择回调
 * @param onStopCasting 停止投屏回调
 */
@Composable
fun OpenCastNavHost(
    context: Context,
    onDeviceSelected: (DiscoveredDevice) -> Unit,
    onStopCasting: () -> Unit
) {
    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = "home"
    ) {
        // 主页 - 设备发现
        composable("home") {
            HomeScreen(
                onDeviceSelected = { device ->
                    onDeviceSelected(device)
                    navController.navigate("casting")
                }
            )
        }

        // 投屏界面
        composable("casting") {
            CastingScreen(
                onStopCasting = {
                    onStopCasting()
                    navController.navigate("home") {
                        popUpTo("home") { inclusive = true }
                    }
                }
            )
        }
    }
}
