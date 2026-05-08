package com.opencast.app.discovery

import java.net.InetAddress

/**
 * 发现设备的数据模型
 *
 * 表示通过 mDNS 发现的接收端设备信息。
 *
 * @property deviceId 设备唯一标识
 * @property deviceName 设备显示名称
 * @property ipAddress 设备 IP 地址
 * @property port 设备服务端口
 * @property signalingPort 信令服务端口
 * @property isOnline 设备是否在线
 * @property lastSeenTime 最后发现时间戳
 */
data class DiscoveredDevice(
    val deviceId: String,
    val deviceName: String,
    val ipAddress: InetAddress,
    val port: Int = DEFAULT_PORT,
    val signalingPort: Int = DEFAULT_SIGNALING_PORT,
    val isOnline: Boolean = true,
    val lastSeenTime: Long = System.currentTimeMillis()
) {
    companion object {
        /** 默认接收端服务端口 */
        const val DEFAULT_PORT = 8080

        /** 默认信令服务端口 */
        const val DEFAULT_SIGNALING_PORT = 8443
    }

    /**
     * 获取设备的完整信令服务器地址
     */
    fun getSignalingUrl(): String {
        return "ws://${ipAddress.hostAddress}:$signalingPort"
    }

    /**
     * 获取设备的显示地址
     */
    fun getDisplayAddress(): String {
        return "${ipAddress.hostAddress}:$port"
    }

    /**
     * 检查设备是否超时（超过指定时间未被发现）
     *
     * @param timeoutMs 超时时间（毫秒），默认 30 秒
     * @return 是否超时
     */
    fun isExpired(timeoutMs: Long = 30_000L): Boolean {
        return System.currentTimeMillis() - lastSeenTime > timeoutMs
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DiscoveredDevice) return false
        return deviceId == other.deviceId
    }

    override fun hashCode(): Int {
        return deviceId.hashCode()
    }
}
