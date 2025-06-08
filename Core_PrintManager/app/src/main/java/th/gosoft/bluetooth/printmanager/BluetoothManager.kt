package th.gosoft.bluetooth.printmanager

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.nio.charset.Charset
import java.util.*

object BluetoothManager {
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var connectedSocket: BluetoothSocket? = null

    // Initialize BluetoothManager with application context
    fun initialize(context: Context) {
        bluetoothAdapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager)?.adapter
        if (bluetoothAdapter == null) {
            throw IllegalStateException("Bluetooth is not supported on this device.")
        }
    }

    // Scan for available Bluetooth devices
    fun scanDevices(context: Context): List<BluetoothDevice> {
        if (bluetoothAdapter == null) {
            throw IllegalStateException("BluetoothManager is not initialized. Call initialize(context) first.")
        }

        if (!bluetoothAdapter!!.isEnabled) {
            throw IllegalStateException("Bluetooth is not enabled. Please enable Bluetooth and try again.")
        }

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("BLUETOOTH_CONNECT permission is not granted.")
        }

        val devices = bluetoothAdapter!!.bondedDevices.toList()
        Log.d("BluetoothManager", "Scanned devices: ${devices.map { it.name }}")
        return devices
    }

    // Connect to a Bluetooth device
    fun connectDevice(context: Context, device: BluetoothDevice): Boolean {
        return try {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                throw SecurityException("Missing required Bluetooth permissions: BLUETOOTH_CONNECT or BLUETOOTH_SCAN.")
            }

            val uuid = device.uuids?.firstOrNull()?.uuid ?: UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
            val socket = device.createRfcommSocketToServiceRecord(uuid)
            bluetoothAdapter?.cancelDiscovery() // Cancel discovery to avoid connection issues
            socket.connect()
            connectedSocket = socket

            // Always rewrite device.json with the latest device information
            val deviceInfo = mapOf(
                "name" to device.name,
                "address" to device.address,
                "uuid" to uuid.toString()
            )
            val file = File(context.filesDir, "device.json")
            file.writeText(JSONObject(deviceInfo).toString())

            true
        } catch (e: IOException) {
            e.printStackTrace()
            false
        } catch (e: SecurityException) {
            e.printStackTrace()
            false
        }
    }

    /**
     * Sends a simple TSC command to the connected printer.
     * This function is intended for testing purposes.
     */
    fun printSimpleTSC(context: Context): Boolean {
        val header = buildTscHeaderCommand(heightMm=20)
        var cls = buildTscCLSCommand()

        val text = buildTscTextCommands("สวัสดีปีใหม่ ").toByteArray()
        val (bitmapCmd, bitmapData) = buildTscBitmapCommandFromStripe()
        val printCmd = buildTscPrintCommand().toByteArray()
        Log.d("BluetoothManager", "printSimpleTSC: header=${header.length}, text=${text.size}, bitmap=${bitmapData.size}, printCmd=${printCmd.size}")
        //val command = header.toByteArray() + cls.toByteArray() + bitmapCmd + bitmapData + text + printCmd
        //Log.d("BluetoothManager", "printSimpleTSC: total command size=${command.size}")

        val commandParts = arrayOf(
            header.toByteArray() +
            cls.toByteArray() + text +
            printCmd,
            header.toByteArray() +
                    cls.toByteArray() + text +
                    printCmd,
            header.toByteArray() +
                    cls.toByteArray() + bitmapCmd +bitmapData + text +
                    printCmd
        )
        for (part in commandParts) {
            return try {

                writeToSocket(context, part)
                writeToSocket(context, part)
                Log.d("BluetoothManager", "printSimpleTSC: Command sent successfully.")
                true
            } catch (e: IOException) {
                e.printStackTrace()
                false
            } catch (e: SecurityException) {
                e.printStackTrace()
                false
            } finally {
                disconnectDevice()
                getConnectedSocket(context)
            }
        }
        return true
    }

    fun printTextTSC(context: Context): Boolean {
        val header = buildTscHeaderCommand(heightMm=20)
        var cls = buildTscCLSCommand()

        val text = buildTscTextCommands("HELLO xxx TSC").toByteArray()
        val (bitmapCmd, bitmapData) = buildTscBitmapCommandFromStripe()
        val printCmd = buildTscPrintCommand().toByteArray()
        Log.d("BluetoothManager", "printTextTSC: header=${header.length}, text=${text.size}, bitmap=${bitmapData.size}, printCmd=${printCmd.size}")
        //val command = header.toByteArray() + cls.toByteArray() + bitmapCmd + bitmapData + text + printCmd
        //Log.d("BluetoothManager", "printTextTSC: total command size=${command.size}")
        return try {
            writeToSocketByChunks(context, header.toByteArray())
            writeToSocketByChunks(context, cls.toByteArray())
            writeToSocketByChunks(context, text)
            var print_result = writeToSocketByChunks(context, printCmd)
            Log.d("BluetoothManager", "printTextTSC: Command sent successfully.")
            print_result

        } catch (e: IOException) {
            e.printStackTrace()
            false
        } catch (e: SecurityException) {
            e.printStackTrace()
            false
        } finally {
            disconnectDevice()
            //      Try to reconnect after disconnect
            getConnectedSocket(context)
        }
    }
    fun printTxtTSC_from_File(context: Context): Boolean {

        val command: ByteArray = try {
            val inputStream = context.assets.open("hello_txt_command.txt")
            val commandString = inputStream.bufferedReader().use { it.readText() }
            Log.d("BluetoothManager", "Loaded command: \n$commandString")
            commandString.toByteArray()
        } catch (e: IOException) {
            Log.e("BluetoothManager", "Failed to load command from hello_txt_command.txt", e)
            return false
        }

        return try {
            writeToSocketByChunks(context, command)
        } catch (e: IOException) {
            e.printStackTrace()
            false
        } catch (e: SecurityException) {
            e.printStackTrace()
            false
        } finally {
            disconnectDevice()
        }
    }

    fun printBitmapTSC_from_File(context: Context): Boolean {
        val command: ByteArray = try {
            val inputStream = context.assets.open("capturescreen.bin")
            inputStream.readBytes().also { inputStream.close() }
        } catch (e: IOException) {
            Log.e("BluetoothManager", "Failed to load capturescreen.bin", e)
            return false
        }

        return try {
            writeToSocketByChunks(context, command)
        } catch (e: IOException) {
            e.printStackTrace()
            false
        } catch (e: SecurityException) {
            e.printStackTrace()
            false
        } finally {
            disconnectDevice()
        }
    }
    /**
     * Disconnects the currently connected Bluetooth device.
     * This function ensures proper cleanup of resources.
     */
    fun disconnectDevice() {
        try {
            if (connectedSocket != null) {
                if (connectedSocket!!.isConnected) {
                    try {
                        connectedSocket!!.outputStream.flush()
                    } catch (e: Exception) {
                        Log.e("BluetoothManager", "Error flushing output stream before close", e)
                    }
                    try {
                        connectedSocket!!.inputStream.close()
                    } catch (e: Exception) {
                        Log.e("BluetoothManager", "Error closing input stream", e)
                    }
                    try {
                        connectedSocket!!.outputStream.close()
                    } catch (e: Exception) {
                        Log.e("BluetoothManager", "Error closing output stream", e)
                    }
                }
                connectedSocket!!.close()
                Log.d("BluetoothManager", "Bluetooth socket closed successfully.")
            }
            connectedSocket = null
        } catch (e: IOException) {
            Log.e("BluetoothManager", "IOException when closing socket", e)
        } catch (e: SecurityException) {
            Log.e("BluetoothManager", "SecurityException when closing socket", e)
        } catch (e: Exception) {
            Log.e("BluetoothManager", "Unexpected exception when closing socket", e)
        }
    }

    // Preview print using the simple TSC command
    // this function is intended for testing purposes from the PrintDialog
    fun previewPrint(context: Context, type: String): Boolean {
        return try {
            Log.d("BluetoothManager", "Attempting to preview print with type: $type")
            if (type == "bitmap") {
                val result = printBitmapTSC_from_File(context);
                Log.e("BluetoothManager", "printBitmapTSC_from_File: $type")
                return result
            } else
            if (type == "textfile") {
                val result = printTxtTSC_from_File(context);
                Log.e("BluetoothManager", "printTxtTSC_from_File: $type")
                return result
            } else
            if (type =="text"){
                val result = printTextTSC(context)
                Log.d("BluetoothManager", "Preview print result: $result")
                return result
            } else
                    if (type =="simple"){
                        val result = printSimpleTSC(context)
                        Log.d("BluetoothManager", "Preview print result: $result")
                        return result
                    } else {
                Log.e("BluetoothManager", "Unsupported print type: $type")
                false
            }
        } catch (e: Exception) {
            Log.e("BluetoothManager", "Error during preview print", e)
            false
        }
    }

    private fun getConnectedSocket(context: Context): BluetoothSocket? {
        if (connectedSocket == null || !connectedSocket!!.isConnected) {
            try {
                // Reinitialize BluetoothManager if needed
                if (bluetoothAdapter == null) {
                    Log.d("BluetoothManager", "Reinitializing BluetoothManager...")
                    initialize(context)
                }

                if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    throw SecurityException("Missing BLUETOOTH_CONNECT permission.")
                }

                val file = File(context.filesDir, "device.json")
                if (file.exists()) {
                    Log.d("BluetoothManager", "Reading device information from device.json...")
                    val deviceInfo = JSONObject(file.readText())
                    val deviceAddress = deviceInfo.getString("address")
                    val device = bluetoothAdapter?.getRemoteDevice(deviceAddress)
                    val uuid = UUID.fromString(deviceInfo.getString("uuid"))

                    if (device != null) {
                        Log.d("BluetoothManager", "Attempting to reconnect to device: $deviceAddress")
                        val socket = device.createRfcommSocketToServiceRecord(uuid)
                        if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED) {
                            bluetoothAdapter?.cancelDiscovery()
                        }
                        socket.connect()
                        connectedSocket = socket
                        Log.d("BluetoothManager", "Reconnection successful.")
                    } else {
                        Log.e("BluetoothManager", "Device not found: $deviceAddress")
                    }
                } else {
                    Log.e("BluetoothManager", "device.json not found.")
                }
            } catch (e: Exception) {
                Log.e("BluetoothManager", "Failed to reconnect to device", e)
                connectedSocket = null
            }
        }
        return connectedSocket
    }

    /**
     * Writes data to the connected socket in chunks of 200 bytes.
     * This method ensures large data is sent in manageable portions.
     */
    private fun writeToSocketByChunks(context:Context, data: ByteArray): Boolean {
        val socket = getConnectedSocket(context = context/* provide context here */)
            ?: run {
                Log.e("BluetoothManager", "Socket is not connected.")
                return false
            }

        return try {
            val outputStream = socket.outputStream
            Log.d("BluetoothManager", "Total data size: ${data.size} bytes")



            val commands = mutableListOf<ByteArray>()
            var start = 0
            for (i in data.indices) {
                if (data[i] == '\n'.code.toByte()) {
                    val end = i + 1
                    commands.add(data.copyOfRange(start, end))
                    start = end
                }
            }
            if (start < data.size) {
                commands.add(data.copyOfRange(start, data.size))
            }
            // Send each command chunk, further split if > 200 bytes
            for (cmd in commands) {


                var offset = 0
                while (offset < cmd.size) {
                    val chunkSize = minOf(200, cmd.size - offset)
                    val chunk = cmd.copyOfRange(offset, offset + chunkSize)
                    Log.d("BluetoothManager", "Writing chunk: offset=$offset, chunkSize=$chunkSize\n" + formatHexAscii(chunk))

                    outputStream.write(chunk)

                    offset += chunkSize
                }
                Log.d("BluetoothManager", "Finished writing command chunk of size ${cmd.size} bytes")
            }

            Log.d("BluetoothManager", "Finished writing to socket.")
            true
        } catch (e: IOException) {
            Log.e("BluetoothManager", "Error writing to socket", e)
            false
        }
    }

    private fun formatHexAscii(data: ByteArray): String {
        val sb = StringBuilder()
        val lineSize = 16
        for (i in data.indices step lineSize) {
            val hexPart = data.slice(i until (i + lineSize).coerceAtMost(data.size))
                .joinToString(" ") { String.format("%02X", it) }
            val asciiPart = data.slice(i until (i + lineSize).coerceAtMost(data.size))
                .map { if (it in 32..126) it.toInt().toChar() else '.' }
                .joinToString("")
            sb.append(String.format("%04X  %-48s  %s\n", i, hexPart, asciiPart))
        }
        return sb.toString()
    }

    /**
     * Writes the entire data to the connected socket in one go.
     * This method ensures the whole data is sent without chunking.
     */
    private fun writeToSocket(context: Context, data: ByteArray): Boolean {
        val socket = getConnectedSocket(context = context/* provide context here */)
            ?: run {
                Log.e("BluetoothManager", "Socket is not connected.")
                return false
            }

        return try {
            val outputStream = socket.outputStream
            Log.d("BluetoothManager", "Writing entire data: size=${data.size} bytes\n${formatHexAscii(data)}")
            outputStream.write(data)
            outputStream.flush() // Ensure data is sent immediately
            Log.d("BluetoothManager", "Finished writing entire data to socket.")
            true
        } catch (e: IOException) {
            Log.e("BluetoothManager", "Error writing to socket", e)
            false
        }
    }

    /**
     * Generates a bitmap byte array for a 100x100 pixel black and white stripe pattern.
     * Each even row is black, each odd row is white.
     * Returns a byte array suitable for TSC BITMAP command (1bpp, left to right, top to bottom).
     */
    fun generateStripeBitmap(width:Int,height:Int): ByteArray {

        val bytesPerRow = (width + 7) / 8 // 1 bit per pixel, padded to byte
        val bitmap = ByteArray(bytesPerRow * height)
        android.util.Log.d("BluetoothManager", "generateStripeBitmap: width=$width, height=$height, bytesPerRow=$bytesPerRow, totalBytes=${bitmap.size}")
        for (y in 0 until height) {
            val isBlack = y % 2 == 0
            val rowStart = y * bytesPerRow
            for (x in 0 until width) {
                if (isBlack) {
                    val byteIndex = rowStart + (x / 8)
                    val bitIndex = 7 - (x % 8)
                    bitmap[byteIndex] = (bitmap[byteIndex].toInt() or (1 shl bitIndex)).toByte()
                }
                // else: leave as 0 (white)
            }
        }

        return bitmap
    }

    /**
     * Builds a TSC TEXT command from a string, splitting by lines and assigning Y positions.
     * @param text The text to print (can be multiline, separated by \n)
     * @param startX The X coordinate for the text (default 100)
     * @param startY The starting Y coordinate (default 20)
     * @param yStep The Y increment for each line (default 30)
     * @param font The font name (default "courmon.TTF")
     * @param rotation The rotation (default 0)
     * @param xMul X multiplier (default 12)
     * @param yMul Y multiplier (default 12)
     * @return The TSC TEXT commands as a string
     */
    /**
     * Builds the TSC CLS (clear image buffer) command.
     * @return The TSC CLS command as a string.
     */
    fun buildTscCLSCommand(): String {
        return "CLS\n"
    }
    fun buildTscTextCommands(
        text: String,
        startX: Int = 100,
        startY: Int = 20,
        yStep: Int = 30,
        font: String = "courmon.TTF",
        rotation: Int = 0,
        xMul: Int = 12,
        yMul: Int = 12
    ): String {
        return text.lines().mapIndexed { idx, line ->
            "TEXT $startX,${startY + idx * yStep},\"$font\",$rotation,$xMul,$yMul,\"$line\""
        }.joinToString("\n") + "\n"
    }

    /**
     * Builds a standard TSC header command string.
     * @param widthMm Label width in mm (default 72)
     * @param heightMm Label height in mm (default 10)
     * @param gapMm Gap height in mm (default 0)
     * @param speed Print speed (default 4)
     * @param density Print density (default 12)
     * @param codepage Codepage (default UTF-8)
     * @param tearOn Whether to set tear on (default true)
     * @param cutterOn Whether to set cutter on (default false)
     * @return The TSC header command as a string
     */
    fun buildTscHeaderCommand(
        widthMm: Int = 72,
        heightMm: Int = 10,
        gapMm: Int = 0,
        speed: Int = 4,
        density: Int = 12,
        codepage: String = "UTF-8",
        tearOn: Boolean = true,
        cutterOn: Boolean = false
    ): String {
        return buildString {
            append("SIZE ${widthMm} mm,${heightMm} mm\n")
            append("GAP ${gapMm} mm,0 mm\n")
            append("SPEED $speed\n")
            append("DENSITY $density\n")
            append("CODEPAGE $codepage\n")
            append("SET TEAR ${if (tearOn) "ON" else "OFF"}\n")
            append("SET CUTTER ${if (cutterOn) "ON" else "OFF"}\n")
            append("DIRECTION 0\n")

        }
    }

    /**
     * Returns the TSC PRINT command string.
     * @param copies Number of copies to print (default 1)
     * @param sets Number of sets to print (default 1)
     * @return The TSC PRINT command as a string
     */
    fun buildTscPrintCommand(copies: Int = 1, sets: Int = 1): String {
        return "PRINT $copies,$sets\n"
    }

    /**
     * Builds a TSC BITMAP command string from the stripe bitmap (100x100px, 1bpp).
     * @param x X position (default 0)
     * @param y Y position (default 0)
     * @return The TSC BITMAP command as a string (with binary data appended)
     */
    fun buildTscBitmapCommandFromStripe(x: Int = 0, y: Int = 0): Pair<ByteArray, ByteArray> {
        val squareSize = 69 // square size working at 69x69
        val width = 300
        val height = 20
        val bytesPerRow = (width + 7) / 8
        val bitmap = generateStripeBitmap(width, height)
        return buildTscBitmapCommand(bitmap, width, height, x, y).also {
            Log.d("BluetoothManager", "buildTscBitmapCommandFromStripe: bitmap size=${bitmap.size}, header=${it.first.size}, data=${it.second.size}")
        }
    }

    /**
     * Builds a TSC BITMAP command from a custom bitmap byte array.
     * @param bitmap The bitmap data (1bpp, left to right, top to bottom)
     * @param width Bitmap width in pixels
     * @param height Bitmap height in pixels
     * @param x X position (default 0)
     * @param y Y position (default 0)
     * @return The TSC BITMAP command as a ByteArray (header + data + newline)
     */
    fun buildTscBitmapCommand(
        bitmap: ByteArray,
        width: Int,
        height: Int,
        x: Int = 0,
        y: Int = 0
    ): Pair<ByteArray, ByteArray> {
        val bytesPerRow = (width + 7) / 8
        val expectedLength = bytesPerRow * height
        Log.d("BluetoothManager", "buildTscBitmapCommand: byteArray length=${bitmap.size}, expected=${expectedLength}")
        val header = "BITMAP $x,$y,$bytesPerRow,$height,1,\n".toByteArray(Charset.forName("ISO-8859-1"))
        return Pair(header, bitmap + "\n".toByteArray())
    }
}
