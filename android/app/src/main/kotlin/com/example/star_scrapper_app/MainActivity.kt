package com.example.star_scrapper_app

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starslibrary/webview_cookies",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getCookies") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrBlank()) {
                result.error("invalid_url", "A URL is required.", null)
                return@setMethodCallHandler
            }
            result.success(CookieManager.getInstance().getCookie(url) ?: "")
        }
    }
}
