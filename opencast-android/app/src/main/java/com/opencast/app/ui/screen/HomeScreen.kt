package com.opencast.app.ui.screen

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.opencast.app.discovery.DiscoveredDevice
import com.opencast.app.ui.theme.*
import com.opencast.app.ui.viewmodel.DeviceViewModel

/**
 * 主页界面
 *
 * 显示发现的设备列表，提供设备选择和投屏启动功能。
 * 支持自动发现和手动输入 IP 地址两种连接方式。
 *
 * @param viewModel 设备发现 ViewModel
 * @param onDeviceSelected 当用户选择设备并确认投屏时的回调
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    viewModel: DeviceViewModel = hiltViewModel(),
    onDeviceSelected: (DiscoveredDevice) -> Unit
) {
    val devices by viewModel.devices.collectAsState()
    val isScanning by viewModel.isScanning.collectAsState()
    val selectedDevice by viewModel.selectedDevice.collectAsState()
    val showManualDialog by viewModel.showManualDialog.collectAsState()
    val manualIp by viewModel.manualIpAddress.collectAsState()
    val manualPort by viewModel.manualPort.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()

    // 错误提示 SnackBar
    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(errorMessage) {
        errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = "OpenCast",
                        style = MaterialTheme.typography.headlineMedium,
                        color = OnPrimary
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Surface
                )
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { viewModel.showManualConnectDialog() },
                containerColor = Primary,
                contentColor = OnPrimary
            ) {
                Icon(Icons.Default.Add, contentDescription = "手动连接")
            }
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp)
        ) {
            Spacer(modifier = Modifier.height(16.dp))

            // 当前设备信息卡片
            CurrentDeviceCard(
                deviceName = viewModel.currentDeviceName,
                deviceId = viewModel.currentDeviceId,
                isScanning = isScanning
            )

            Spacer(modifier = Modifier.height(24.dp))

            // 设备列表标题
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "发现的设备",
                    style = MaterialTheme.typography.titleLarge,
                    color = OnBackground
                )

                // 扫描状态指示器
                if (isScanning) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            color = Primary,
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "扫描中",
                            style = MaterialTheme.typography.bodyMedium,
                            color = OnSurfaceVariant
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // 设备列表
            if (devices.isEmpty()) {
                EmptyDeviceList()
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxSize()
                ) {
                    items(
                        items = devices,
                        key = { it.deviceId }
                    ) { device ->
                        DeviceItem(
                            device = device,
                            isSelected = selectedDevice?.deviceId == device.deviceId,
                            onClick = { viewModel.selectDevice(device) }
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // 连接按钮
            AnimatedVisibility(
                visible = selectedDevice != null,
                enter = fadeIn(),
                exit = fadeOut()
            ) {
                selectedDevice?.let { device ->
                    Button(
                        onClick = { onDeviceSelected(device) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp),
                        shape = RoundedCornerShape(16.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Primary,
                            contentColor = OnPrimary
                        )
                    ) {
                        Icon(
                            Icons.Default.Cast,
                            contentDescription = null,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "连接到 ${device.deviceName}",
                            style = MaterialTheme.typography.labelLarge
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }

    // 手动连接对话框
    if (showManualDialog) {
        ManualConnectDialog(
            ipAddress = manualIp,
            port = manualPort.toString(),
            onIpChange = { viewModel.updateManualIpAddress(it) },
            onPortChange = { viewModel.updateManualPort(it) },
            onConfirm = { viewModel.confirmManualConnect() },
            onDismiss = { viewModel.hideManualConnectDialog() }
        )
    }
}

/**
 * 当前设备信息卡片
 */
@Composable
private fun CurrentDeviceCard(
    deviceName: String,
    deviceId: String,
    isScanning: Boolean
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = SurfaceVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 设备图标
            Surface(
                modifier = Modifier.size(48.dp),
                shape = CircleShape,
                color = Primary.copy(alpha = 0.15f)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.Default.PhoneAndroid,
                        contentDescription = null,
                        modifier = Modifier.size(24.dp),
                        tint = Primary
                    )
                }
            }

            Spacer(modifier = Modifier.width(16.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = deviceName,
                    style = MaterialTheme.typography.titleLarge,
                    color = OnSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "ID: $deviceId",
                    style = MaterialTheme.typography.bodyMedium,
                    color = OnSurfaceVariant
                )
            }

            // 扫描状态指示
            Surface(
                modifier = Modifier.size(12.dp),
                shape = CircleShape,
                color = if (isScanning) CastingActive else CastingInactive
            ) {}
        }
    }
}

/**
 * 设备列表项
 */
@Composable
private fun DeviceItem(
    device: DiscoveredDevice,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) Primary.copy(alpha = 0.15f) else SurfaceVariant
        ),
        elevation = CardDefaults.cardElevation(
            defaultElevation = if (isSelected) 4.dp else 0.dp
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 设备图标
            Surface(
                modifier = Modifier.size(44.dp),
                shape = RoundedCornerShape(12.dp),
                color = if (isSelected) Primary else Surface
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.Default.Tv,
                        contentDescription = null,
                        modifier = Modifier.size(22.dp),
                        tint = if (isSelected) OnPrimary else OnSurfaceVariant
                    )
                }
            }

            Spacer(modifier = Modifier.width(14.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = device.deviceName,
                    style = MaterialTheme.typography.titleLarge,
                    color = OnSurface,
                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = device.getDisplayAddress(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = OnSurfaceVariant
                )
            }

            // 在线状态
            if (isSelected) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = "已选择",
                    tint = Primary,
                    modifier = Modifier.size(24.dp)
                )
            } else {
                Surface(
                    modifier = Modifier.size(8.dp),
                    shape = CircleShape,
                    color = CastingActive
                ) {}
            }
        }
    }
}

/**
 * 空设备列表提示
 */
@Composable
private fun EmptyDeviceList() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                Icons.Default.DevicesOther,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = OnSurfaceVariant.copy(alpha = 0.5f)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "未发现设备",
                style = MaterialTheme.typography.titleLarge,
                color = OnSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "请确保接收端设备与当前设备在同一网络下",
                style = MaterialTheme.typography.bodyMedium,
                color = OnSurfaceVariant.copy(alpha = 0.7f)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "或点击右下角 + 按钮手动输入 IP 地址",
                style = MaterialTheme.typography.bodyMedium,
                color = Primary
            )
        }
    }
}

/**
 * 手动连接对话框
 */
@Composable
private fun ManualConnectDialog(
    ipAddress: String,
    port: String,
    onIpChange: (String) -> Unit,
    onPortChange: (String) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = "手动连接",
                style = MaterialTheme.typography.headlineMedium,
                color = OnSurface
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = ipAddress,
                    onValueChange = onIpChange,
                    label = { Text("接收端 IP 地址") },
                    placeholder = { Text("例如: 192.168.1.100") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Primary,
                        unfocusedBorderColor = OnSurfaceVariant,
                        cursorColor = Primary
                    )
                )

                OutlinedTextField(
                    value = port,
                    onValueChange = onPortChange,
                    label = { Text("端口") },
                    placeholder = { Text("8080") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Primary,
                        unfocusedBorderColor = OnSurfaceVariant,
                        cursorColor = Primary
                    )
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = onConfirm,
                enabled = ipAddress.isNotBlank()
            ) {
                Text("连接", color = Primary)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消", color = OnSurfaceVariant)
            }
        },
        containerColor = Surface,
        shape = RoundedCornerShape(20.dp)
    )
}
