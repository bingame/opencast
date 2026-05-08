package com.opencast.app

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

/**
 * OpenCast 应用程序入口
 *
 * 使用 Hilt 进行依赖注入管理。
 * 负责全局初始化工作，如 WebRTC、日志等。
 */
@HiltAndroidApp
class OpenCastApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        // 全局初始化可以在这里进行
        // 例如：WebRTC 初始化、日志配置、崩溃上报等
    }
}
