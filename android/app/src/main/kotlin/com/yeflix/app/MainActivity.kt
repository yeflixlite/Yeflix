package com.yeflix.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.platform.PlatformViewRegistry

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registra la vista nativa de ExoPlayer para que Flutter pueda embeberla vía AndroidView.
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.yeflix.app/exoplayer",
            ExoPlayerPlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
