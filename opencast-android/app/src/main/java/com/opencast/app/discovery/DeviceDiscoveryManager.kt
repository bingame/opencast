package com.opencast.app.discovery

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiManager.MulticastLock
import android.os.Build
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.net.InetAddress
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.jmdns.JmDNS
import javax.jmdns.ServiceEvent
import javax.jmdns.ServiceInfo
import javax.jmdns.ServiceListener
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * mDNS 设备发现管理器
 *
 * 使用 JmDNS 实现局域网内的设备自动发现。
 * 通过广播和监听 _opencast._tcp.local 服务类型来发现接收端设备。
 *
 * @param context 应用上下文
 */
class DeviceDiscoveryManager(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val TAG = "DeviceDiscovery"

        /** mDNS 服务类型 */
        private const val SERVICE_TYPE = "_opencast._tcp.local"

        /** 设备发现超时时间（毫秒） */
        private const val DEVICE_TIMEOUT_MS = 30_000L

        /** 清理过期设备的间隔（毫秒） */
        private const val CLEANUP_INTERVAL_MS = 10_000L
    }

    /** 发现的设备列表 */
    private val _discoveredDevices = MutableStateFlow<List<DiscoveredDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<DiscoveredDevice>> = _discoveredDevices.asStateFlow()

    /** 是否正在扫描 */
    private val _isScanning = MutableStateFlow(false)
    val isScanning: StateFlow<Boolean> = _isScanning.asStateFlow()

    /** JmDNS 实例 */
    private var jmdns: JmDNS? = null

    /** 多播锁，用于在 Android 上接收多播数据包 */
    private var multicastLock: MulticastLock? = null

    /** 已发现设备的缓存（线程安全） */
    private val deviceCache = ConcurrentHashMap<String, DiscoveredDevice>()

    /** 当前设备 ID */
    private val deviceId: String = UUID.randomUUID().toString().substring(0, 8)

    /** 协程作用域 */
    private val scope = CoroutineScope(Dispatchers.IO)

    /**
     * 启动设备发现
     *
     * 初始化 JmDNS，注册服务监听器，并开始广播自身服务。
     */
    fun startDiscovery() {
        if (_isScanning.value) return

        scope.launch {
            try {
                _isScanning.value = true

                // 获取多播锁（Android 需要持有此锁才能接收多播数据包）
                acquireMulticastLock()

                // 创建 JmDNS 实例
                jmdns = createJmDNS()

                // 注册服务监听器
                jmdns?.addServiceListener(SERVICE_TYPE, object : ServiceListener {
                    override fun serviceAdded(event: ServiceEvent) {
                        // 服务被发现，获取详细信息
                        jmdns?.requestServiceInfo(event.type, event.name)
                    }

                    override fun serviceResolved(event: ServiceEvent) {
                        // 服务信息已解析，添加到设备列表
                        val info = event.info
                        handleDeviceDiscovered(info)
                    }

                    override fun serviceRemoved(event: ServiceEvent) {
                        // 服务已移除，从设备列表中删除
                        handleDeviceRemoved(event.name)
                    }
                })

                // 广播自身服务信息
                registerService()

                // 启动过期设备清理任务
                startCleanupTask()

            } catch (e: Exception) {
                _isScanning.value = false
                e.printStackTrace()
            }
        }
    }

    /**
     * 停止设备发现
     *
     * 注销服务监听器，关闭 JmDNS 实例，释放多播锁。
     */
    fun stopDiscovery() {
        try {
            jmdns?.unregisterAllServices()
            jmdns?.close()
            jmdns = null
            releaseMulticastLock()
            deviceCache.clear()
            _discoveredDevices.value = emptyList()
            _isScanning.value = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 手动添加设备（通过 IP 地址连接时使用）
     *
     * @param ipAddress 设备 IP 地址
     * @param port 设备端口
     * @param signalingPort 信令端口
     */
    fun addManualDevice(ipAddress: String, port: Int = 8080, signalingPort: Int = 8443) {
        scope.launch {
            try {
                val address = InetAddress.getByName(ipAddress)
                val device = DiscoveredDevice(
                    deviceId = "manual-${address.hostAddress}",
                    deviceName = "手动设备 ($ipAddress)",
                    ipAddress = address,
                    port = port,
                    signalingPort = signalingPort,
                    isOnline = true,
                    lastSeenTime = System.currentTimeMillis()
                )
                deviceCache[device.deviceId] = device
                updateDeviceList()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /**
     * 获取当前设备 ID
     */
    fun getCurrentDeviceId(): String = deviceId

    /**
     * 获取当前设备名称
     */
    fun getCurrentDeviceName(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL}"
    }

    /**
     * 获取多播锁
     */
    private fun acquireMulticastLock() {
        try {
            val wifiManager = context.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifiManager.createMulticastLock(TAG).apply {
                setReferenceCounted(true)
                acquire()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 释放多播锁
     */
    private fun releaseMulticastLock() {
        try {
            multicastLock?.release()
            multicastLock = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 创建 JmDNS 实例
     */
    private suspend fun createJmDNS(): JmDNS? {
        return try {
            suspendCoroutine { continuation ->
                Thread {
                    try {
                        val instance = JmDNS.create()
                        continuation.resume(instance)
                    } catch (e: Exception) {
                        continuation.resume(null)
                    }
                }.start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    /**
     * 注册自身服务信息
     *
     * 将当前设备信息通过 mDNS 广播出去，
     * 使其他设备可以发现本设备。
     */
    private fun registerService() {
        try {
            val serviceInfo = ServiceInfo.create(
                SERVICE_TYPE,
                "OpenCast-$deviceId",
                "",  // 不需要描述
                DiscoveredDevice.DEFAULT_PORT,
                mapOf(
                    "deviceId" to deviceId,
                    "deviceName" to getCurrentDeviceName(),
                    "signalingPort" to DiscoveredDevice.DEFAULT_SIGNALING_PORT.toString()
                )
            )
            jmdns?.registerService(serviceInfo)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 处理发现的设备
     */
    private fun handleDeviceDiscovered(info: ServiceInfo) {
        scope.launch {
            try {
                val addresses = info.inet4Addresses
                if (addresses.isEmpty()) return@launch

                val device = DiscoveredDevice(
                    deviceId = info.getProperty("deviceId") ?: info.name,
                    deviceName = info.getProperty("deviceName") ?: info.name,
                    ipAddress = addresses.first(),
                    port = info.port,
                    signalingPort = (info.getProperty("signalingPort")
                        ?: DiscoveredDevice.DEFAULT_SIGNALING_PORT.toString()).toInt(),
                    isOnline = true,
                    lastSeenTime = System.currentTimeMillis()
                )

                // 更新设备缓存
                deviceCache[device.deviceId] = device
                updateDeviceList()

            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /**
     * 处理设备移除
     */
    private fun handleDeviceRemoved(serviceName: String) {
        scope.launch {
            deviceCache.remove(serviceName)
            updateDeviceList()
        }
    }

    /**
     * 更新设备列表（过滤过期设备并排序）
     */
    private fun updateDeviceList() {
        val now = System.currentTimeMillis()
        val validDevices = deviceCache.values
            .filter { it.isOnline && (now - it.lastSeenTime) < DEVICE_TIMEOUT_MS }
            .sortedByDescending { it.lastSeenTime }

        _discoveredDevices.value = validDevices
    }

    /**
     * 启动过期设备清理任务
     */
    private fun startCleanupTask() {
        scope.launch {
            while (_isScanning.value) {
                kotlinx.coroutines.delay(CLEANUP_INTERVAL_MS)
                updateDeviceList()
            }
        }
    }
}
