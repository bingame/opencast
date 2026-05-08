package com.opencast.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opencast.app.discovery.DeviceDiscoveryManager
import com.opencast.app.discovery.DiscoveredDevice
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * 设备发现 ViewModel
 *
 * 管理设备发现状态，暴露设备列表给 UI 层。
 * 处理设备选择和连接请求。
 *
 * @property discoveryManager 设备发现管理器（由 Hilt 注入）
 */
@HiltViewModel
class DeviceViewModel @Inject constructor(
    private val discoveryManager: DeviceDiscoveryManager
) : ViewModel() {

    companion object {
        private const val TAG = "DeviceViewModel"
    }

    /** 发现的设备列表 */
    val devices: StateFlow<List<DiscoveredDevice>> = discoveryManager.discoveredDevices
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyList()
        )

    /** 是否正在扫描 */
    val isScanning: StateFlow<Boolean> = discoveryManager.isScanning
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = false
        )

    /** 当前设备名称 */
    val currentDeviceName: String = discoveryManager.getCurrentDeviceName()

    /** 当前设备 ID */
    val currentDeviceId: String = discoveryManager.getCurrentDeviceId()

    /** 选中的设备 */
    private val _selectedDevice = MutableStateFlow<DiscoveredDevice?>(null)
    val selectedDevice: StateFlow<DiscoveredDevice?> = _selectedDevice.asStateFlow()

    /** 手动输入的 IP 地址 */
    private val _manualIpAddress = MutableStateFlow("")
    val manualIpAddress: StateFlow<String> = _manualIpAddress.asStateFlow()

    /** 手动输入的端口 */
    private val _manualPort = MutableStateFlow(8080)
    val manualPort: StateFlow<Int> = _manualPort.asStateFlow()

    /** 手动连接对话框是否显示 */
    private val _showManualDialog = MutableStateFlow(false)
    val showManualDialog: StateFlow<Boolean> = _showManualDialog.asStateFlow()

    /** 错误消息 */
    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    init {
        // ViewModel 初始化时自动开始设备发现
        startDiscovery()
    }

    /**
     * 开始设备发现
     */
    fun startDiscovery() {
        viewModelScope.launch {
            try {
                discoveryManager.startDiscovery()
            } catch (e: Exception) {
                _errorMessage.value = "设备发现启动失败: ${e.message}"
            }
        }
    }

    /**
     * 停止设备发现
     */
    fun stopDiscovery() {
        discoveryManager.stopDiscovery()
    }

    /**
     * 选择设备
     *
     * @param device 要连接的设备
     */
    fun selectDevice(device: DiscoveredDevice) {
        _selectedDevice.value = device
    }

    /**
     * 取消选择设备
     */
    fun deselectDevice() {
        _selectedDevice.value = null
    }

    /**
     * 更新手动输入的 IP 地址
     */
    fun updateManualIpAddress(ip: String) {
        _manualIpAddress.value = ip
    }

    /**
     * 更新手动输入的端口
     */
    fun updateManualPort(port: String) {
        _manualPort.value = port.toIntOrNull() ?: 8080
    }

    /**
     * 显示手动连接对话框
     */
    fun showManualConnectDialog() {
        _showManualDialog.value = true
    }

    /**
     * 隐藏手动连接对话框
     */
    fun hideManualConnectDialog() {
        _showManualDialog.value = false
    }

    /**
     * 确认手动连接
     *
     * 验证 IP 地址格式，添加手动设备。
     */
    fun confirmManualConnect() {
        val ip = _manualIpAddress.value.trim()
        if (ip.isEmpty() || !isValidIpAddress(ip)) {
            _errorMessage.value = "请输入有效的 IP 地址"
            return
        }

        val port = _manualPort.value
        discoveryManager.addManualDevice(ip, port)

        // 查找刚添加的设备并选中
        viewModelScope.launch {
            discoveryManager.discoveredDevices.collect { devices ->
                val manualDevice = devices.find {
                    it.ipAddress.hostAddress == ip && it.port == port
                }
                if (manualDevice != null) {
                    _selectedDevice.value = manualDevice
                    _showManualDialog.value = false
                    _manualIpAddress.value = ""
                    _manualPort.value = 8080
                    return@collect
                }
            }
        }
    }

    /**
     * 清除错误消息
     */
    fun clearError() {
        _errorMessage.value = null
    }

    /**
     * 验证 IP 地址格式
     */
    private fun isValidIpAddress(ip: String): Boolean {
        val pattern = Regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")
        return pattern.matches(ip)
    }

    override fun onCleared() {
        super.onCleared()
        discoveryManager.stopDiscovery()
    }
}
