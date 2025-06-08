package th.gosoft.bluetooth.printmanager

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.util.ArrayList
import org.json.JSONObject
import th.gosoft.bluetooth.printmanager.ui.theme.CoreApplicationTheme

class ListedDevices : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 1)
            return
        }
        val scannedDevices = BluetoothManager.scanDevices(this)
        val deviceNames = ArrayList(scannedDevices.map { it.name ?: "Unknown Device" })
        setContent {
            CoreApplicationTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    DeviceListScreen(Modifier.padding(innerPadding))
                }
            }
        }
    }
}

@Composable
fun DeviceListScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val activityContext = context as? Activity ?: throw IllegalStateException("Context is not an Activity")
    val deviceNames = context.intent.getStringArrayListExtra("deviceNames") ?: arrayListOf()
    var selectedIndex by remember { mutableStateOf(-1) }
    Column(
        modifier = modifier
            .background(Color(0xFFF5F5F5))
            .padding(16.dp),
        verticalArrangement = Arrangement.Top,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "PrintManager - Devices",
            style = MaterialTheme.typography.headlineSmall,
            color = Color(0xFF1A237E),
            modifier = Modifier.padding(bottom = 16.dp)
        )
        if (deviceNames.isEmpty()) {
            Text(
                text = "No devices found.",
                color = Color.Gray,
                modifier = Modifier.padding(24.dp)
            )
        } else {
            deviceNames.forEachIndexed { index, name ->
                val isSelected = index == selectedIndex
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                        .then(
                            if (isSelected) Modifier.background(
                                color = Color(0xFFE3F2FD),
                                shape = RoundedCornerShape(8.dp)
                            ) else Modifier
                        )
                        .border(
                            width = if (isSelected) 2.dp else 1.dp,
                            color = if (isSelected) Color(0xFF1976D2) else Color(0xFF1A237E),
                            shape = RoundedCornerShape(8.dp)
                        )
                        .clickable { selectedIndex = index },
                    colors = CardDefaults.cardColors(containerColor = Color.Transparent),
                    elevation = CardDefaults.cardElevation(2.dp)
                ) {
                    Text(
                        text = name,
                        color = if (isSelected) Color(0xFF1976D2) else Color(0xFF1A237E),
                        modifier = Modifier.padding(16.dp)
                    )
                }
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Select a device to connect and print.",
            color = Color.DarkGray,
            style = MaterialTheme.typography.bodyMedium
        )
        Spacer(modifier = Modifier.weight(1f))
        Button(
            onClick = {
                if (selectedIndex != -1) {
                    val selectedDevice = deviceNames[selectedIndex]
                    // Ensure permissions are checked before accessing Bluetooth
                    if (ContextCompat.checkSelfPermission(activityContext, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED ||
                        ContextCompat.checkSelfPermission(activityContext, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                        ActivityCompat.requestPermissions(
                            activityContext,
                            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT),
                            1
                        )
                        android.widget.Toast.makeText(activityContext, "Please grant Bluetooth permissions.", android.widget.Toast.LENGTH_LONG).show()
                        return@Button
                    }
                    val pairedDevices = BluetoothManager.scanDevices(activityContext)
                    val device = pairedDevices.find { it.name == selectedDevice || it.address == selectedDevice }
                    if (device != null) {
                        val socket = BluetoothManager.connectDevice(activityContext, device)
                        if (socket) {
                            val intent = Intent(activityContext, PrintDialog::class.java)
                            activityContext.startActivity(intent)
                        } else {
                            android.widget.Toast.makeText(activityContext, "Failed to connect.", android.widget.Toast.LENGTH_LONG).show()
                        }
                    } else {
                        android.widget.Toast.makeText(activityContext, "Device not paired.", android.widget.Toast.LENGTH_LONG).show()
                    }
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp),
            enabled = selectedIndex != -1,
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2))
        ) {
            Text("Connect", color = Color.White)
        }
    }
}
