package com.opencast.app.ui.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opencast.app.discovery.DiscoveredDevice
import com.opencast.app.service.ScreenCaptureService
import com.opencast.app.webrtc.WebRTCClient
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * 投屏控制 ViewModel
 *
 * 管理 WebRTC 连接状态，控制投屏的开始和停止。
 * 暴露连接状态、延迟等信息给 UI 层。
 *
 * @property webRTCClient WebRTC 客户端（由 Hilt 注入）
 */
@HiltViewModel
class CastingViewModel @Inject constructor(
    private val webRTCClient: WebRTCClient
) : ViewModel() {

    companion object {
        private const val TAG = "CastingViewModel"
    }

    /** WebRTC 连接状态 */
    val connectionState: StateFlow<WebRTCClient.ConnectionState> = webRTCClient.connectionState
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = WebRTCClient.ConnectionState.IDLE
        )

    /** 连接延迟（毫秒） */
    val latency: StateFlow<Long> = webRTCClient.latency
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = 0L
        )

    /** 是否正在投屏 */
    val isCasting: StateFlow<Boolean> = MutableStateFlow(false)

    /** 目标设备 */
    private val _targetDevice = MutableStateFlow<DiscoveredDevice?>(null)
    val targetDevice: StateFlow<DiscoveredDevice?> = _targetDevice.asStateFlow()

    /** 投屏分辨率宽度 */
    private val _resolutionWidth = MutableStateFlow(0)
    val resolutionWidth: StateFlow<Int> = _resolutionWidth.asStateFlow()

    /** 投屏分辨率高度 */
    private val _resolutionHeight = MutableStateFlow(0)
    val resolutionHeight: StateFlow<Int> = _resolutionHeight.asStateFlow()

    /** 投屏帧率 */
    private val _fps = MutableStateFlow(0)
    val fps: StateFlow<Int> = _fps.asStateFlow()

    /** 错误消息 */
    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    /** 是否显示停止确认对话框 */
    private val _showStopDialog = MutableStateFlow(false)
    val showStopDialog: StateFlow<Boolean> = _showStopDialog.asStateFlow()

    init {
        // 监听连接状态变化
        viewModelScope.launch {
            webRTCClient.connectionState.collect { state ->
                when (state) {
                    WebRTCClient.ConnectionState.CONNECTED -> {
                        (isCasting as MutableStateFlow).value = true
                        _errorMessage.value = null
                    }
                    WebRTCClient.ConnectionState.FAILED -> {
                        (isCasting as MutableStateFlow).value = false
                        _errorMessage.value = "投屏连接失败，请检查网络后重试"
                    }
                    WebRTCClient.ConnectionState.DISCONNECTED -> {
                        (isCasting as MutableStateFlow).value = false
                    }
                    else -> {}
                }
            }
        }
    }

    /**
     * 设置目标设备
     *
     * @param device 要投屏到的设备
     */
    fun setTargetDevice(device: DiscoveredDevice) {
        _targetDevice.value = device
    }

    /**
     * 请求开始投屏
     *
     * 此方法仅设置目标设备，实际的投屏启动由 ScreenCaptureService 完成。
     * Activity 需要先获取 MediaProjection 授权，然后启动 Service。
     */
    fun requestStartCasting(device: DiscoveredDevice) {
        _targetDevice.value = device
        _errorMessage.value = null
        Log.d(TAG, "请求开始投屏到: ${device.deviceName} (${device.getDisplayAddress()})")
    }

    /**
     * 请求停止投屏
     */
    fun requestStopCasting() {
        _showStopDialog.value = true
    }

    /**
     * 确认停止投屏
     */
    fun confirmStopCasting() {
        viewModelScope.launch {
            try {
                webRTCClient.stopCasting()
                (isCasting as MutableStateFlow).value = false
                _targetDevice.value = null
                _showStopDialog.value = false
                Log.d(TAG, "投屏已停止")
            } catch (e: Exception) {
                Log.e(TAG, "停止投屏失败", e)
                _errorMessage.value = "停止投屏失败: ${e.message}"
            }
        }
    }

    /**
     * 取消停止投屏
     */
    fun cancelStopCasting() {
        _showStopDialog.value = false
    }

    /**
     * 更新投屏统计信息
     *
     * @param width 分辨率宽度
     * @param height 分辨率高度
     * @param framesPerSecond 帧率
     */
    fun updateStats(width: Int, height: Int, framesPerSecond: Int) {
        _resolutionWidth.value = width
        _resolutionHeight.value = height
        _fps.value = framesPerSecond
    }

    /**
     * 清除错误消息
     */
    fun clearError() {
        _errorMessage.value = null
    }

    /**
     * 获取连接状态的文字描述
     */
    fun getConnectionStateText(): String {
        return when (connectionState.value) {
            WebRTCClient.ConnectionState.IDLE -> "就绪"
            WebRTCClient.ConnectionState.CREATING -> "正在创建连接…"
            WebRTCClient.ConnectionState.CONNECTING -> "正在连接…"
            WebRTCClient.ConnectionState.CONNECTED -> "已连接"
            WebRTCClient.ConnectionState.FAILED -> "连接失败"
            WebRTCClient.ConnectionState.DISCONNECTED -> "已断开"
            WebRTCClient.ConnectionState.CLOSED -> "已关闭"
        }
    }

    override fun onCleared() {
        super.onCleared()
        // ViewModel 销毁时不断开连接，由 Service 管理
    }
}
