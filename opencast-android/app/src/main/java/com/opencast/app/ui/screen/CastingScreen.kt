package com.opencast.app.ui.screen

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.CastConnected
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.opencast.app.ui.theme.*
import com.opencast.app.ui.viewmodel.CastingViewModel
import com.opencast.app.webrtc.WebRTCClient

/**
 * 投屏中界面
 *
 * 全屏显示投屏状态，包括连接信息、延迟、分辨率、帧率等。
 * 提供停止投屏按钮和连接状态动画。
 *
 * @param viewModel 投屏控制 ViewModel
 * @param onStopCasting 停止投屏回调
 */
@Composable
fun CastingScreen(
    viewModel: CastingViewModel = hiltViewModel(),
    onStopCasting: () -> Unit
) {
    val connectionState by viewModel.connectionState.collectAsState()
    val latency by viewModel.latency.collectAsState()
    val resolutionWidth by viewModel.resolutionWidth.collectAsState()
    val resolutionHeight by viewModel.resolutionHeight.collectAsState()
    val fps by viewModel.fps.collectAsState()
    val targetDevice by viewModel.targetDevice.collectAsState()
    val showStopDialog by viewModel.showStopDialog.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    // 连接状态动画
    val infiniteTransition = rememberInfiniteTransition(label = "casting")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse"
    )

    // 连接状态颜色
    val statusColor by animateColorAsState(
        targetValue = when (connectionState) {
            WebRTCClient.ConnectionState.CONNECTED -> CastingActive
            WebRTCClient.ConnectionState.CONNECTING,
            WebRTCClient.ConnectionState.CREATING -> Primary
            WebRTCClient.ConnectionState.FAILED -> Error
            else -> CastingInactive
        },
        animationSpec = tween(300),
        label = "statusColor"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // 投屏状态图标
            Surface(
                modifier = Modifier
                    .size(120.dp)
                    .alpha(pulseAlpha),
                shape = CircleShape,
                color = statusColor.copy(alpha = 0.15f)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = if (connectionState == WebRTCClient.ConnectionState.CONNECTED) {
                            Icons.Default.CastConnected
                        } else {
                            Icons.Default.Cast
                        },
                        contentDescription = null,
                        modifier = Modifier.size(56.dp),
                        tint = statusColor
                    )
                }
            }

            Spacer(modifier = Modifier.height(32.dp))

            // 投屏状态文字
            Text(
                text = when (connectionState) {
                    WebRTCClient.ConnectionState.CONNECTED -> "正在投屏"
                    WebRTCClient.ConnectionState.CONNECTING -> "正在连接…"
                    WebRTCClient.ConnectionState.CREATING -> "正在创建连接…"
                    WebRTCClient.ConnectionState.FAILED -> "连接失败"
                    WebRTCClient.ConnectionState.DISCONNECTED -> "已断开连接"
                    else -> "准备中…"
                },
                style = MaterialTheme.typography.headlineLarge,
                color = OnBackground,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(8.dp))

            // 目标设备名称
            targetDevice?.let { device ->
                Text(
                    text = "投屏到: ${device.deviceName}",
                    style = MaterialTheme.typography.bodyLarge,
                    color = OnSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }

            Spacer(modifier = Modifier.height(40.dp))

            // 连接信息卡片
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(
                    containerColor = SurfaceVariant
                )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    // 连接状态
                    InfoRow(
                        icon = { Icon(Icons.Default.Wifi, null, tint = statusColor) },
                        label = "连接状态",
                        value = viewModel.getConnectionStateText(),
                        valueColor = statusColor
                    )

                    // 延迟
                    InfoRow(
                        icon = {
                            Surface(
                                modifier = Modifier.size(8.dp),
                                shape = CircleShape,
                                color = if (latency < 100) CastingActive
                                else if (latency < 300) Warning
                                else Error
                            ) {}
                        },
                        label = "延迟",
                        value = "${latency} ms",
                        valueColor = if (latency < 100) CastingActive
                        else if (latency < 300) Warning
                        else Error
                    )

                    // 分辨率
                    if (resolutionWidth > 0 && resolutionHeight > 0) {
                        InfoRow(
                            icon = {
                                Surface(
                                    modifier = Modifier.size(8.dp),
                                    shape = CircleShape,
                                    color = OnSurfaceVariant
                                ) {}
                            },
                            label = "分辨率",
                            value = "${resolutionWidth} x ${resolutionHeight}",
                            valueColor = OnSurface
                        )
                    }

                    // 帧率
                    if (fps > 0) {
                        InfoRow(
                            icon = {
                                Surface(
                                    modifier = Modifier.size(8.dp),
                                    shape = CircleShape,
                                    color = OnSurfaceVariant
                                ) {}
                            },
                            label = "帧率",
                            value = "$fps fps",
                            valueColor = OnSurface
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(40.dp))

            // 停止投屏按钮
            Button(
                onClick = { viewModel.requestStopCasting() },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Error.copy(alpha = 0.15f),
                    contentColor = Error
                )
            ) {
                Icon(
                    Icons.Default.Stop,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp)
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "停止投屏",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }

    // 停止确认对话框
    if (showStopDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.cancelStopCasting() },
            title = {
                Text(
                    text = "停止投屏",
                    style = MaterialTheme.typography.headlineMedium,
                    color = OnSurface
                )
            },
            text = {
                Text(
                    text = "确定要停止投屏吗？",
                    style = MaterialTheme.typography.bodyLarge,
                    color = OnSurfaceVariant
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.confirmStopCasting()
                        onStopCasting()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Error,
                        contentColor = OnPrimary
                    )
                ) {
                    Text("确定停止")
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { viewModel.cancelStopCasting() }) {
                    Text("取消", color = OnSurfaceVariant)
                }
            },
            containerColor = Surface,
            shape = RoundedCornerShape(20.dp)
        )
    }

    // 错误提示
    errorMessage?.let { error ->
        LaunchedEffect(error) {
            // 可以使用 SnackBar 显示错误
            viewModel.clearError()
        }
    }
}

/**
 * 信息行组件
 */
@Composable
private fun InfoRow(
    icon: @Composable () -> Unit,
    label: String,
    value: String,
    valueColor: Color = OnSurface
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        icon()
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = OnSurfaceVariant,
            modifier = Modifier.width(80.dp)
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
            color = valueColor,
            fontWeight = FontWeight.Medium
        )
    }
}
