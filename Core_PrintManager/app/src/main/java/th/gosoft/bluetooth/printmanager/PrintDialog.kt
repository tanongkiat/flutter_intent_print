package th.gosoft.bluetooth.printmanager

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import org.json.JSONObject
import java.io.File
import th.gosoft.bluetooth.printmanager.ui.theme.CoreApplicationTheme

class PrintDialog : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            CoreApplicationTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    PrintDialogScreen(Modifier.padding(innerPadding))
                }
            }
        }
    }
}

@Composable
fun PrintDialogScreen(modifier: Modifier = Modifier) {
    val printTypes = listOf("text", "bitmap")
    val selectedType = remember { mutableStateOf("text") } // Default to "text"
    Column(
        modifier = modifier
            .background(Color(0xFFF5F5F5))
            .padding(16.dp),
        verticalArrangement = Arrangement.Top,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "PrintManager - Preview",
            style = androidx.compose.material3.MaterialTheme.typography.headlineSmall,
            color = Color(0xFF1A237E),
            modifier = Modifier.padding(bottom = 16.dp)
        )
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp)
                .border(
                    width = 2.dp,
                    color = Color(0xFF1976D2),
                    shape = RoundedCornerShape(8.dp)
                )
                .background(
                    color = Color(0xFFE3F2FD),
                    shape = RoundedCornerShape(8.dp)
                ),
            colors = CardDefaults.cardColors(containerColor = Color.Transparent),
            elevation = CardDefaults.cardElevation(2.dp)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Image(
                    painter = painterResource(id = android.R.drawable.ic_menu_gallery),
                    contentDescription = "Preview",
                    modifier = Modifier.size(96.dp)
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "No device selected",
                    color = Color(0xFF1976D2)
                )
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "Select Print Type:",
            style = androidx.compose.material3.MaterialTheme.typography.bodyMedium
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.RadioButton(
                selected = selectedType.value == "text",
                onClick = { selectedType.value = "text" }
            )
            Text("Text", modifier = Modifier.padding(start = 8.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.RadioButton(
                selected = selectedType.value == "bitmap",
                onClick = { selectedType.value = "bitmap" }
            )
            Text("Bitmap", modifier = Modifier.padding(start = 8.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.RadioButton(
                selected = selectedType.value == "textfile",
                onClick = { selectedType.value = "textfile" }
            )
            Text("Text File", modifier = Modifier.padding(start = 8.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.RadioButton(
                selected = selectedType.value == "simple",
                onClick = { selectedType.value = "simple" }
            )
            Text("Simple TSC", modifier = Modifier.padding(start = 8.dp))
        }
        Spacer(modifier = Modifier.weight(1f))
        val context = LocalContext.current
        Button(
            onClick = {
                val type = selectedType.value // Use the selected print type
                val success = BluetoothManager.previewPrint(context, type)
                if (!success) {
                    android.widget.Toast.makeText(context, "Failed to preview print.", android.widget.Toast.LENGTH_LONG).show()
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp),
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2))
        ) {
            Text("Print", color = Color.White)
        }
    }
}
