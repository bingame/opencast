package com.opencast.app.di

import android.content.Context
import com.opencast.app.discovery.DeviceDiscoveryManager
import com.opencast.app.webrtc.SignalingClient
import com.opencast.app.webrtc.WebRTCClient
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Hilt 依赖注入模块
 *
 * 提供全局单例依赖：
 * - WebRTCClient: WebRTC 连接管理
 * - SignalingClient: 信令通信客户端
 * - DeviceDiscoveryManager: 设备发现管理器
 */
@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    /**
     * 提供 WebRTC 客户端单例
     */
    @Provides
    @Singleton
    fun provideWebRTCClient(
        @ApplicationContext context: Context,
        signalingClient: SignalingClient
    ): WebRTCClient {
        return WebRTCClient(context, signalingClient)
    }

    /**
     * 提供信令客户端单例
     */
    @Provides
    @Singleton
    fun provideSignalingClient(): SignalingClient {
        return SignalingClient()
    }

    /**
     * 提供设备发现管理器单例
     */
    @Provides
    @Singleton
    fun provideDeviceDiscoveryManager(
        @ApplicationContext context: Context
    ): DeviceDiscoveryManager {
        return DeviceDiscoveryManager(context)
    }
}
