package com.yeflix.app

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

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
                "inspectApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("no_path", "Ruta del APK vacía", null)
                    } else {
                        try {
                            result.success(inspectApk(path))
                        } catch (t: Throwable) {
                            result.error(
                                "inspect_error",
                                t.message ?: t.javaClass.simpleName,
                                null
                            )
                        }
                    }
                }
                "installedApkAbis" -> {
                    try {
                        result.success(installedApkAbis())
                    } catch (t: Throwable) {
                        result.error(
                            "abi_error",
                            t.message ?: t.javaClass.simpleName,
                            null
                        )
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

    /**
     * Lee los metadatos del APK descargado y comprueba que se puede instalar
     * encima de esta app: mismo paquete, misma firma y versionCode mayor.
     */
    private fun inspectApk(path: String): Map<String, Any?> {
        val file = File(path)
        require(file.exists()) { "El APK no existe: $path" }

        val pm = packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

        val archive = pm.getPackageArchiveInfo(path, flags)
            ?: throw IllegalArgumentException("No se pudo leer el APK")
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            archive.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            archive.versionCode.toLong()
        }

        val apkSignatures = signaturesOf(archive)
        val self = pm.getPackageInfo(packageName, flags)
        val selfSignatures = signaturesOf(self)
        val signatureMatches = apkSignatures.isNotEmpty() &&
            selfSignatures.isNotEmpty() &&
            apkSignatures.toSet() == selfSignatures.toSet()

        return mapOf(
            "packageName" to (archive.packageName ?: ""),
            "versionCode" to versionCode,
            "versionName" to (archive.versionName ?: ""),
            "signatureSha256" to apkSignatures.firstOrNull(),
            "installedSignatureSha256" to selfSignatures.firstOrNull(),
            "signatureMatches" to signatureMatches
        )
    }

    /** ABIs nativas contenidas en el APK instalado. */
    private fun installedApkAbis(): List<String> {
        val sourceDir = applicationInfo.sourceDir ?: return emptyList()
        val abis = linkedSetOf<String>()
        java.util.zip.ZipFile(sourceDir).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val name = entries.nextElement().name
                if (!name.startsWith("lib/")) continue
                val parts = name.split('/')
                if (parts.size >= 3) abis.add(parts[1])
            }
        }
        return abis.toList()
    }

    /** SHA-256 de los certificados de firma actuales del paquete. */
    @Suppress("DEPRECATION")
    private fun signaturesOf(info: PackageInfo): List<String> {
        val certificates: Array<Signature>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        if (certificates == null) return emptyList()
        return certificates.map { signature ->
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
            digest.joinToString("") { "%02x".format(it) }
        }
    }
}
