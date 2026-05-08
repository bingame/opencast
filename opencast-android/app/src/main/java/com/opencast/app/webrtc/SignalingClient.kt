package com.opencast.app.webrtc

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonParser
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import okio.ByteString
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * 信令客户端
 *
 * 使用 OkHttp WebSocket 连接信令服务器，
 * 实现 SDP 交换和 ICE 候选交换。
 *
 * 信令消息类型：
 * - REGISTER: 注册设备
 * - OFFER: SDP Offer
 * - ANSWER: SDP Answer
 * - ICE_CANDIDATE: ICE 候选
 * - BYE: 断开连接
 * - ERROR: 错误消息
 */
@Singleton
class SignalingClient @Inject constructor() {

    companion object {
        private const val TAG = "SignalingClient"

        /** 信令服务器默认地址 */
        private const val DEFAULT_SIGNALING_URL = "ws://192.168.1.100:8443"

        /** 心跳间隔（秒） */
        private const val HEARTBEAT_INTERVAL = 30L

        /** 重连间隔（毫秒） */
        private const val RECONNECT_DELAY = 3000L

        /** 最大重连次数 */
        private const val MAX_RECONNECT_ATTEMPTS = 5
    }

    /** OkHttp 客户端 */
    private val okHttpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .pingInterval(HEARTBEAT_INTERVAL, TimeUnit.SECONDS)
            .build()
    }

    /** WebSocket 连接 */
    private var webSocket: WebSocket? = null

    /** 信令服务器 URL */
    private var serverUrl: String = DEFAULT_SIGNALING_URL

    /** 连接状态 */
    private val _connectionState = MutableStateFlow(SignalingState.DISCONNECTED)
    val connectionState: StateFlow<SignalingState> = _connectionState.asStateFlow()

    /** 信令消息回调 */
    private var messageCallback: SignalingMessageCallback? = null

    /** 重连次数 */
    private var reconnectAttempts = 0

    /** 协程作用域 */
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** Gson 序列化器 */
    private val gson = Gson()

    /**
     * 信令连接状态
     */
    enum class SignalingState {
        /** 已断开 */
        DISCONNECTED,
        /** 正在连接 */
        CONNECTING,
        /** 已连接 */
        CONNECTED,
        /** 重连中 */
        RECONNECTING,
        /** 连接失败 */
        FAILED
    }

    /**
     * 信令消息回调接口
     */
    interface SignalingMessageCallback {
        /** 收到 SDP Offer */
        fun onOffer(sdp: String)
        /** 收到 SDP Answer */
        fun onAnswer(sdp: String)
        /** 收到 ICE 候选 */
        fun onIceCandidate(sdpMid: String, sdpMLineIndex: Int, sdp: String)
        /** 连接状态变化 */
        fun onConnectionStateChanged(state: SignalingState)
        /** 收到错误消息 */
        fun onError(message: String)
        /** 收到设备注册确认 */
        fun onRegistered(deviceId: String)
    }

    /**
     * 设置消息回调
     */
    fun setCallback(callback: SignalingMessageCallback?) {
        messageCallback = callback
    }

    /**
     * 连接信令服务器
     *
     * @param url 信令服务器地址（ws://host:port）
     */
    fun connect(url: String = serverUrl) {
        if (_connectionState.value == SignalingState.CONNECTED ||
            _connectionState.value == SignalingState.CONNECTING
        ) {
            Log.w(TAG, "信令服务器已连接或正在连接中")
            return
        }

        serverUrl = url
        _connectionState.value = SignalingState.CONNECTING
        reconnectAttempts = 0

        val request = Request.Builder()
            .url(url)
            .build()

        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "信令服务器已连接: $url")
                _connectionState.value = SignalingState.CONNECTED
                reconnectAttempts = 0
                messageCallback?.onConnectionStateChanged(SignalingState.CONNECTED)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.d(TAG, "收到信令消息: $text")
                handleMessage(text)
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                Log.d(TAG, "收到二进制消息: ${bytes.size()} bytes")
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "信令服务器正在关闭: code=$code, reason=$reason")
                webSocket.close(1000, null)
                _connectionState.value = SignalingState.DISCONNECTED
                messageCallback?.onConnectionStateChanged(SignalingState.DISCONNECTED)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "信令服务器已关闭: code=$code, reason=$reason")
                _connectionState.value = SignalingState.DISCONNECTED
                messageCallback?.onConnectionStateChanged(SignalingState.DISCONNECTED)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "信令服务器连接失败", t)
                _connectionState.value = SignalingState.FAILED
                messageCallback?.onConnectionStateChanged(SignalingState.FAILED)
                messageCallback?.onError(t.message ?: "连接失败")

                // 自动重连
                attemptReconnect()
            }
        })
    }

    /**
     * 断开信令服务器连接
     */
    fun disconnect() {
        reconnectAttempts = MAX_RECONNECT_ATTEMPTS // 阻止自动重连
        webSocket?.close(1000, "用户主动断开")
        webSocket = null
        _connectionState.value = SignalingState.DISCONNECTED
    }

    /**
     * 发送注册消息
     *
     * @param deviceId 设备 ID
     * @param deviceName 设备名称
     */
    fun sendRegister(deviceId: String, deviceName: String) {
        val message = mapOf(
            "type" to "REGISTER",
            "deviceId" to deviceId,
            "deviceName" to deviceName
        )
        sendMessage(gson.toJson(message))
    }

    /**
     * 发送 SDP Offer
     *
     * @param sdp SDP 描述
     * @param targetDeviceId 目标设备 ID
     */
    fun sendOffer(sdp: String, targetDeviceId: String) {
        val message = mapOf(
            "type" to "OFFER",
            "sdp" to sdp,
            "targetDeviceId" to targetDeviceId
        )
        sendMessage(gson.toJson(message))
    }

    /**
     * 发送 SDP Answer
     *
     * @param sdp SDP 描述
     * @param targetDeviceId 目标设备 ID
     */
    fun sendAnswer(sdp: String, targetDeviceId: String) {
        val message = mapOf(
            "type" to "ANSWER",
            "sdp" to sdp,
            "targetDeviceId" to targetDeviceId
        )
        sendMessage(gson.toJson(message))
    }

    /**
     * 发送 ICE 候选
     *
     * @param sdpMid SDP 媒体标识
     * @param sdpMLineIndex SDP 媒体行索引
     * @param sdp ICE 候选 SDP
     * @param targetDeviceId 目标设备 ID
     */
    fun sendIceCandidate(sdpMid: String, sdpMLineIndex: Int, sdp: String, targetDeviceId: String) {
        val message = mapOf(
            "type" to "ICE_CANDIDATE",
            "sdpMid" to sdpMid,
            "sdpMLineIndex" to sdpMLineIndex,
            "candidate" to sdp,
            "targetDeviceId" to targetDeviceId
        )
        sendMessage(gson.toJson(message))
    }

    /**
     * 发送断开连接消息
     *
     * @param targetDeviceId 目标设备 ID
     */
    fun sendBye(targetDeviceId: String) {
        val message = mapOf(
            "type" to "BYE",
            "targetDeviceId" to targetDeviceId
        )
        sendMessage(gson.toJson(message))
    }

    /**
     * 发送文本消息
     */
    private fun sendMessage(text: String): Boolean {
        val ws = webSocket
        if (ws == null) {
            Log.w(TAG, "WebSocket 未连接，无法发送消息")
            return false
        }

        return ws.send(text)
    }

    /**
     * 处理收到的信令消息
     */
    private fun handleMessage(text: String) {
        try {
            val json = JsonParser.parseString(text).asJsonObject
            val type = json.get("type")?.asString ?: return

            scope.launch {
                when (type) {
                    "OFFER" -> {
                        val sdp = json.get("sdp")?.asString ?: return@launch
                        messageCallback?.onOffer(sdp)
                    }
                    "ANSWER" -> {
                        val sdp = json.get("sdp")?.asString ?: return@launch
                        messageCallback?.onAnswer(sdp)
                    }
                    "ICE_CANDIDATE" -> {
                        val sdpMid = json.get("sdpMid")?.asString ?: return@launch
                        val sdpMLineIndex = json.get("sdpMLineIndex")?.asInt ?: return@launch
                        val candidate = json.get("candidate")?.asString ?: return@launch
                        messageCallback?.onIceCandidate(sdpMid, sdpMLineIndex, candidate)
                    }
                    "REGISTER_ACK" -> {
                        val deviceId = json.get("deviceId")?.asString ?: return@launch
                        messageCallback?.onRegistered(deviceId)
                    }
                    "ERROR" -> {
                        val message = json.get("message")?.asString ?: "未知错误"
                        messageCallback?.onError(message)
                    }
                    else -> {
                        Log.w(TAG, "未知的信令消息类型: $type")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "解析信令消息失败", e)
        }
    }

    /**
     * 尝试自动重连
     */
    private fun attemptReconnect() {
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            Log.w(TAG, "已达到最大重连次数，停止重连")
            return
        }

        reconnectAttempts++
        _connectionState.value = SignalingState.RECONNECTING
        messageCallback?.onConnectionStateChanged(SignalingState.RECONNECTING)

        Log.d(TAG, "尝试重连 ($reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...")

        scope.launch {
            delay(RECONNECT_DELAY * reconnectAttempts) // 指数退避
            if (_connectionState.value == SignalingState.RECONNECTING) {
                connect(serverUrl)
            }
        }
    }

    /**
     * 获取当前连接状态
     */
    fun getState(): SignalingState = _connectionState.value

    /**
     * 释放资源
     */
    fun dispose() {
        disconnect()
        scope.cancel()
    }
}
