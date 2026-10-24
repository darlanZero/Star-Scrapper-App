package com.example.star_scrapper_app

import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starslibrary/webview_cookies",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("invalid_url", "A URL is required.", null)
                        return@setMethodCallHandler
                    }
                    result.success(CookieManager.getInstance().getCookie(url) ?: "")
                }
                "loadHtml" -> loadHtmlInWebView(
                    url = call.argument<String>("url"),
                    userAgent = call.argument<String>("userAgent"),
                    readySelector = call.argument<String>("readySelector"),
                    result = result,
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun loadHtmlInWebView(
        url: String?,
        userAgent: String?,
        readySelector: String?,
        result: MethodChannel.Result,
    ) {
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "A URL is required.", null)
            return
        }
        val handler = Handler(Looper.getMainLooper())
        val webView = WebView(this)
        val layoutParams = FrameLayout.LayoutParams(1, 1)
        webView.alpha = 0.01f
        webView.translationX = -10f
        webView.translationY = -10f
        addContentView(webView, layoutParams)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        if (!userAgent.isNullOrBlank()) webView.settings.userAgentString = userAgent
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        CookieManager.getInstance().flush()

        var finished = false
        fun dispose() {
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.stopLoading()
            webView.destroy()
        }
        fun finishWithHtml() {
            if (finished) return
            webView.evaluateJavascript("document.documentElement.outerHTML") { html ->
                if (finished) return@evaluateJavascript
                finished = true
                result.success(html ?: "")
                dispose()
            }
        }
        fun probe() {
            if (finished) return
            val selector = JSONObject.quote(readySelector ?: "main, body")
            webView.evaluateJavascript(
                "Boolean(document.querySelector($selector))",
            ) { ready ->
                if (finished) return@evaluateJavascript
                if (ready == "true") finishWithHtml()
                else handler.postDelayed({ probe() }, 500)
            }
        }

        val timeout = Runnable { finishWithHtml() }
        handler.postDelayed(timeout, 20_000)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                handler.postDelayed({ probe() }, 350)
            }
        }
        webView.loadUrl(url)
    }
}
