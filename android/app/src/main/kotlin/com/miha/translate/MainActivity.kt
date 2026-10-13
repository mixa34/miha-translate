package com.miha.translate

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.os.Messenger
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.jetbrains.annotations.NotNull
import java.lang.reflect.Method
import android.content.Intent.getIntent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Parcelable
import java.security.MessageDigest

// import `in`.jvapps.system_alert_window.SystemAlertWindowPlugin
// import io.flutter.app.FlutterApplication
// import io.flutter.plugin.common.PluginRegistry
// import io.flutter.plugin.common.PluginRegistry.PluginRegistrantCallback

class MainActivity: FlutterActivity() {

    private val TRANSLATE_CHANNEL_NAME = "com.miha.translate/translate"
    private val MIHASECURE_CHANNEL_NAME = "com.miha.translate/mihasecure"
    private var translateChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NotNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Setup Channels
        setupChannels(this,flutterEngine.dartExecutor.binaryMessenger)

    }

    private fun setupChannels(context:Context, messenger: BinaryMessenger){
        translateChannel = MethodChannel(messenger, TRANSLATE_CHANNEL_NAME)
        translateChannel!!.setMethodCallHandler{
            call, result ->
            if (call.method == "getText"){
                result.success(text)
                text = ""
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(messenger, MIHASECURE_CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method == "verify") {
                val status = MihaSecure.verify(context)
                // Without MihaSecure, shared text is dropped, never handed over.
                if (status != MihaSecure.VERIFIED) text = ""
                result.success(status)
            } else {
                result.notImplemented()
            }
        }
    }
    private fun teardownChannels(){
        teardownChannels()
        translateChannel!!.setMethodCallHandler(null)
    }




}
var text = ""

/**
 * Checks that the authentic MihaSecure app is installed for the current user:
 * the package [PACKAGE], signed with the certificate whose SHA-256 is
 * [CERTIFICATE_SHA256] (taken from the MihaSecure APK given to clients).
 *
 * A lightweight local check, not tamper-proof DRM.
 */
object MihaSecure {
    const val PACKAGE = "net.mihalabs.mihasecure"
    const val VERIFIED = "verified"
    const val NOT_INSTALLED = "not_installed"
    const val SIGNATURE_MISMATCH = "signature_mismatch"
    const val ERROR = "error"

    private val CERTIFICATE_SHA256 =
        "ff8b8d7f90816eb5a3e08f0b1902dbbc6aa7379b5b5b6cf1000bdd38a3faf687".chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    fun verify(context: Context): String = try {
        val packageManager = context.packageManager
        try {
            packageManager.getPackageInfo(PACKAGE, 0)
            if (isSignedByMihaSecure(packageManager)) VERIFIED else SIGNATURE_MISMATCH
        } catch (e: PackageManager.NameNotFoundException) {
            // Not installed, or not visible to this app.
            NOT_INSTALLED
        }
    } catch (e: Exception) {
        ERROR
    }

    private fun isSignedByMihaSecure(packageManager: PackageManager): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Takes signing key rotation into account.
            return packageManager.hasSigningCertificate(PACKAGE, CERTIFICATE_SHA256, PackageManager.CERT_INPUT_SHA256)
        }
        @Suppress("DEPRECATION")
        val signatures = packageManager.getPackageInfo(PACKAGE, PackageManager.GET_SIGNATURES).signatures
        if (signatures == null || signatures.isEmpty()) return false
        // Every signer must be MihaSecure's.
        return signatures.all { sha256(it.toByteArray()).contentEquals(CERTIFICATE_SHA256) }
    }

    private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)
}

class UppercaseActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

       // Nothing (not the word "null") when the extra is missing.
       text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString() ?: ""

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        launchIntent?.let { startActivity(it) }
        finish()

    }

}

class SharedActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Nothing (not the word "null") when the extra is missing.
        text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: ""

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        launchIntent?.let { startActivity(it) }
        finish()

    }

}


// class Application : FlutterApplication(), PluginRegistrantCallback {
//     override fun onCreate() {
//         super.onCreate()
//         SystemAlertWindowPlugin.setPluginRegistrant(this)
//     }

//     override fun registerWith(registry: PluginRegistry) {
//     SystemAlertWindowPlugin.registerWith(registry.registrarFor("in.jvapps.system_alert_window"));
//     }
// }