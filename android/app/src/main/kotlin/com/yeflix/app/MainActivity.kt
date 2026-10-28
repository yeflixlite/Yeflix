package com.yeflix.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registra la vista nativa de ExoPlayer para que Flutter pueda embeberla vía AndroidView.
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.yeflix.app/exoplayer",
            ExoPlayerPlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        // Canal para instalar el APK de actualización desde la propia app.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.yeflix.app/installer"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallPermissionSettings" -> {
                    try {
                        openInstallPermissionSettings()
                        result.success(null)
                    } catch (t: Throwable) {
                        result.error("settings_error", t.message ?: "unknown", null)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("no_path", "Ruta del APK vacía", null)
                    } else {
                        try {
                            installApk(path)
                            result.success(null)
                        } catch (t: Throwable) {
                            result.error(
                                "install_error",
                                t.message ?: t.javaClass.simpleName,
                                null
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** true si Android permite a esta app abrir el instalador de paquetes. */
    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /** Abre la pantalla "Instalar apps desconocidas" para esta app. */
    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
        }
    }

    /** Lanza el instalador del sistema con el APK descargado. */
    private fun installApk(path: String) {
        val file = File(path)
        require(file.exists()) { "El APK no existe: $path" }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
