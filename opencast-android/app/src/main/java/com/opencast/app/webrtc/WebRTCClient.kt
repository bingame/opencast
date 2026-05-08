package com.opencast.app.webrtc

import android.content.Context
import android.media.projection.MediaProjection
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.webrtc.*
import java.util.concurrent.ConcurrentHashMap

/**
 * WebRTC 客户端核心
 *
 * 管理 WebRTC 连接的完整生命周期：
 * - 创建和配置 PeerConnectionFactory
 * - 创建 PeerConnection
 * - 添加本地音视频轨道
 * - SDP Offer/Answer 交换
 * - ICE 候选处理
 * - 连接状态监听
 *
 * @param context 应用上下文
 * @param signalingClient 信令客户端
 */
class WebRTCClient(
    private val context: Context,
    private val signalingClient: SignalingClient
) {
    companion object {
        private const val TAG = "WebRTCClient"

        /** STUN 服务器列表 */
        private val ICE_SERVERS = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").create(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").create(),
            PeerConnection.IceServer.builder("stun:stun2.l.google.com:19302").create()
        )

        /** 视频编码参数 */
        private const val VIDEO_WIDTH = 1280
        private const val VIDEO_HEIGHT = 720
        private const val VIDEO_FPS = 30
        private const val VIDEO_BITRATE = 2_500_000 // 2.5 Mbps
    }

    /** WebRTC 连接状态 */
    enum class ConnectionState {
        /** 未连接 */
        IDLE,
        /** 正在创建连接 */
        CREATING,
        /** 正在连接 */
        CONNECTING,
        /** 已连接 */
        CONNECTED,
        /** 连接失败 */
        FAILED,
        /** 已断开 */
        DISCONNECTED,
        /** 连接已关闭 */
        CLOSED
    }

    /** 连接状态流 */
    private val _connectionState = MutableStateFlow(ConnectionState.IDLE)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    /** 延迟信息（毫秒） */
    private val _latency = MutableStateFlow(0L)
    val latency: StateFlow<Long> = _latency.asStateFlow()

    /** PeerConnectionFactory */
    private var peerConnectionFactory: PeerConnectionFactory? = null

    /** PeerConnection */
    private var peerConnection: PeerConnection? = null

    /** 屏幕采集器 */
    private var screenCapturer: ScreenCapturer? = null

    /** 协程作用域 */
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** ICE 候选队列（在 PeerConnection 创建前收到的候选暂存于此） */
    private val pendingIceCandidates = mutableListOf<IceCandidate>()

    /** SDP 媒体约束 */
    private val sdpMediaConstraints = MediaConstraints().apply {
        mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "false"))
        mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "false"))
    }

    /** 连接状态回调 */
    private var onConnectionStateChangeListener: ((ConnectionState) -> Unit)? = null

    init {
        // 初始化信令客户端回调
        initSignalingCallback()
    }

    /**
     * 初始化 WebRTC
     *
     * 创建 PeerConnectionFactory，配置 H.264 硬件编码。
     *
     * @return 初始化是否成功
     */
    fun initialize(): Boolean {
        return try {
            // 初始化 WebRTC 库（只需调用一次）
            val initializationOptions = PeerConnectionFactory.InitializationOptions
                .builder(context)
                .setEnableInternalTracer(false)
                .createInitializationOptions()
            PeerConnectionFactory.initialize(initializationOptions)

            // 创建编码解码器工厂（启用 H.264 硬件编码）
            val videoEncoderFactory = DefaultVideoEncoderFactory(
                null,  // 使用默认的 EGL 上下文
                true,  // 启用 Intel VP8 编码器
                true   // 启用 H.264 硬件编码
            )
            val videoDecoderFactory = DefaultVideoDecoderFactory(null)

            // 创建 PeerConnectionFactory
            val options = PeerConnectionFactory.Options()
            peerConnectionFactory = PeerConnectionFactory.builder()
                .setVideoEncoderFactory(videoEncoderFactory)
                .setVideoDecoderFactory(videoDecoderFactory)
                .setOptions(options)
                .create()

            // 创建屏幕采集器
            screenCapturer = ScreenCapturer(context)

            Log.d(TAG, "WebRTC 初始化成功")
            true
        } catch (e: Exception) {
            Log.e(TAG, "WebRTC 初始化失败", e)
            false
        }
    }

    /**
     * 开始投屏
     *
     * @param mediaProjection MediaProjection 授权
     * @param resultCode 授权结果码
     * @param data 授权 Intent 数据
     * @param targetDeviceId 目标设备 ID
     */
    fun startCasting(
        mediaProjection: MediaProjection,
        resultCode: Int,
        data: android.content.Intent,
        targetDeviceId: String
    ) {
        scope.launch {
            try {
                _connectionState.value = ConnectionState.CREATING

                // 初始化屏幕采集
                val capturer = screenCapturer ?: return@launch
                val factory = peerConnectionFactory ?: return@launch

                val success = capturer.initialize(
                    mediaProjection, resultCode, data, factory
                )
                if (!success) {
                    _connectionState.value = ConnectionState.FAILED
                    return@launch
                }

                // 创建 PeerConnection
                createPeerConnection()

                // 添加本地媒体轨道
                addLocalTracks()

                // 开始屏幕采集
                capturer.startCapture(VIDEO_WIDTH, VIDEO_HEIGHT, VIDEO_FPS)

                // 创建 SDP Offer
                createOffer(targetDeviceId)

            } catch (e: Exception) {
                Log.e(TAG, "开始投屏失败", e)
                _connectionState.value = ConnectionState.FAILED
            }
        }
    }

    /**
     * 停止投屏
     */
    fun stopCasting() {
        scope.launch {
            try {
                // 停止屏幕采集
                screenCapturer?.stopCapture()

                // 关闭 PeerConnection
                peerConnection?.close()
                peerConnection = null

                // 清空待处理 ICE 候选
                pendingIceCandidates.clear()

                _connectionState.value = ConnectionState.DISCONNECTED
                Log.d(TAG, "投屏已停止")
            } catch (e: Exception) {
                Log.e(TAG, "停止投屏失败", e)
            }
        }
    }

    /**
     * 创建 PeerConnection
     */
    private fun createPeerConnection() {
        val factory = peerConnectionFactory ?: return

        val rtcConfig = PeerConnection.RTCConfiguration(ICE_SERVERS).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            // 启用 TCP 候选（NAT 穿透更好）
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.ENABLED
            // 候选网络策略
            candidateNetworkPolicy = PeerConnection.CandidateNetworkPolicy.ALL
            // 音频抖动缓冲
            audioJitterBufferMaxPackets = 50
            audioJitterBufferFastAccelerate = true
            // 编码配置
            enableCpuOveruseDetection = true
        }

        peerConnection = factory.createPeerConnection(
            rtcConfig,
            object : PeerConnection.Observer {
                override fun onSignalingChange(state: PeerConnection.SignalingState?) {
                    Log.d(TAG, "信令状态变化: $state")
                }

                override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
                    Log.d(TAG, "ICE 连接状态变化: $state")
                    when (state) {
                        PeerConnection.IceConnectionState.CONNECTED,
                        PeerConnection.IceConnectionState.COMPLETED -> {
                            _connectionState.value = ConnectionState.CONNECTED
                        }
                        PeerConnection.IceConnectionState.DISCONNECTED -> {
                            _connectionState.value = ConnectionState.DISCONNECTED
                        }
                        PeerConnection.IceConnectionState.FAILED -> {
                            _connectionState.value = ConnectionState.FAILED
                        }
                        PeerConnection.IceConnectionState.CHECKING -> {
                            _connectionState.value = ConnectionState.CONNECTING
                        }
                        else -> {}
                    }
                    onConnectionStateChangeListener?.invoke(_connectionState.value)
                }

                override fun onIceConnectionReceivingChange(receiving: Boolean) {
                    Log.d(TAG, "ICE 接收状态变化: receiving=$receiving")
                }

                override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {
                    Log.d(TAG, "ICE 收集状态变化: $state")
                }

                override fun onIceCandidate(candidate: IceCandidate?) {
                    if (candidate != null) {
                        Log.d(TAG, "发现 ICE 候选: ${candidate.sdp}")
                        // 通过信令服务器发送 ICE 候选
                        signalingClient.sendIceCandidate(
                            candidate.sdpMid,
                            candidate.sdpMLineIndex,
                            candidate.sdp,
                            "" // 目标设备 ID 由信令服务器路由
                        )
                    }
                }

                override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {
                    Log.d(TAG, "ICE 候选已移除: ${candidates?.size}")
                }

                override fun onAddStream(stream: MediaStream?) {
                    Log.d(TAG, "收到远端媒体流")
                }

                override fun onRemoveStream(stream: MediaStream?) {
                    Log.d(TAG, "远端媒体流已移除")
                }

                override fun onDataChannel(channel: DataChannel?) {
                    Log.d(TAG, "收到数据通道")
                }

                override fun onRenegotiationNeeded() {
                    Log.d(TAG, "需要重新协商")
                }

                override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {
                    Log.d(TAG, "添加远端轨道")
                }
            }
        )
    }

    /**
     * 添加本地媒体轨道到 PeerConnection
     */
    private fun addLocalTracks() {
        val pc = peerConnection ?: return

        // 添加视频轨道
        screenCapturer?.getVideoTrack()?.let { track ->
            pc.addTrack(track)
            Log.d(TAG, "已添加本地视频轨道")
        }

        // 添加音频轨道
        screenCapturer?.getAudioTrack()?.let { track ->
            pc.addTrack(track)
            Log.d(TAG, "已添加本地音频轨道")
        }
    }

    /**
     * 创建 SDP Offer
     */
    private fun createOffer(targetDeviceId: String) {
        val pc = peerConnection ?: return

        pc.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription?) {
                if (sdp != null) {
                    Log.d(TAG, "SDP Offer 创建成功")
                    pc.setLocalDescription(object : SdpObserver {
                        override fun onCreateSuccess(p0: SessionDescription?) {}
                        override fun onSetSuccess() {
                            Log.d(TAG, "本地 SDP Offer 设置成功")
                            // 通过信令服务器发送 Offer
                            signalingClient.sendOffer(sdp.description, targetDeviceId)
                        }

                        override fun onCreateFailure(error: String?) {
                            Log.e(TAG, "创建 SDP 失败: $error")
                            _connectionState.value = ConnectionState.FAILED
                        }

                        override fun onSetFailure(error: String?) {
                            Log.e(TAG, "设置本地 SDP 失败: $error")
                            _connectionState.value = ConnectionState.FAILED
                        }
                    }, sdp)
                }
            }

            override fun onSetSuccess() {}
            override fun onCreateFailure(error: String?) {
                Log.e(TAG, "创建 Offer 失败: $error")
                _connectionState.value = ConnectionState.FAILED
            }

            override fun onSetFailure(error: String?) {
                Log.e(TAG, "设置 Offer 失败: $error")
                _connectionState.value = ConnectionState.FAILED
            }
        }, sdpMediaConstraints)
    }

    /**
     * 处理收到的 SDP Answer
     *
     * @param sdp SDP Answer 描述
     */
    fun handleRemoteAnswer(sdp: String) {
        scope.launch {
            val pc = peerConnection ?: return@launch

            val remoteSdp = SessionDescription(SessionDescription.Type.ANSWER, sdp)
            pc.setRemoteDescription(object : SdpObserver {
                override fun onCreateSuccess(p0: SessionDescription?) {}
                override fun onSetSuccess() {
                    Log.d(TAG, "远端 SDP Answer 设置成功")
                }

                override fun onCreateFailure(error: String?) {
                    Log.e(TAG, "创建 SDP 失败: $error")
                }

                override fun onSetFailure(error: String?) {
                    Log.e(TAG, "设置远端 SDP Answer 失败: $error")
                    _connectionState.value = ConnectionState.FAILED
                }
            }, remoteSdp)
        }
    }

    /**
     * 处理收到的 ICE 候选
     *
     * @param sdpMid SDP 媒体标识
     * @param sdpMLineIndex SDP 媒体行索引
     * @param sdp ICE 候选 SDP
     */
    fun handleRemoteIceCandidate(sdpMid: String, sdpMLineIndex: Int, sdp: String) {
        scope.launch {
            val pc = peerConnection
            if (pc == null) {
                // PeerConnection 尚未创建，暂存候选
                pendingIceCandidates.add(IceCandidate(sdpMid, sdpMLineIndex, sdp))
                return@launch
            }

            val candidate = IceCandidate(sdpMid, sdpMLineIndex, sdp)
            pc.addIceCandidate(candidate)
            Log.d(TAG, "已添加远端 ICE 候选")
        }
    }

    /**
     * 设置连接状态变化监听器
     */
    fun setOnConnectionStateChangeListener(listener: (ConnectionState) -> Unit) {
        onConnectionStateChangeListener = listener
    }

    /**
     * 获取当前连接状态
     */
    fun getState(): ConnectionState = _connectionState.value

    /**
     * 释放所有资源
     */
    fun dispose() {
        stopCasting()
        screenCapturer?.dispose()
        screenCapturer = null
        peerConnectionFactory?.dispose()
        peerConnectionFactory = null
        scope.cancel()
        Log.d(TAG, "WebRTC 资源已释放")
    }

    /**
     * 初始化信令客户端回调
     */
    private fun initSignalingCallback() {
        signalingClient.setCallback(object : SignalingClient.SignalingMessageCallback {
            override fun onOffer(sdp: String) {
                // 接收端场景：处理远端 Offer 并回复 Answer
                // 在投屏发送端场景中一般不会收到 Offer
                Log.d(TAG, "收到远端 Offer（当前为发送端，忽略）")
            }

            override fun onAnswer(sdp: String) {
                // 收到接收端的 Answer，设置远端 SDP
                handleRemoteAnswer(sdp)
            }

            override fun onIceCandidate(sdpMid: String, sdpMLineIndex: Int, sdp: String) {
                // 收到远端 ICE 候选
                handleRemoteIceCandidate(sdpMid, sdpMLineIndex, sdp)
            }

            override fun onConnectionStateChanged(state: SignalingClient.SignalingState) {
                Log.d(TAG, "信令状态变化: $state")
                if (state == SignalingClient.SignalingState.DISCONNECTED ||
                    state == SignalingClient.SignalingState.FAILED
                ) {
                    _connectionState.value = ConnectionState.DISCONNECTED
                }
            }

            override fun onError(message: String) {
                Log.e(TAG, "信令错误: $message")
            }

            override fun onRegistered(deviceId: String) {
                Log.d(TAG, "设备已注册: $deviceId")
            }
        })
    }
}
