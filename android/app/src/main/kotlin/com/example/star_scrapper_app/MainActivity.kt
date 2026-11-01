package com.example.star_scrapper_app

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Rect
import android.webkit.JavascriptInterface
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity: FlutterActivity() {
    private var readerWebView: WebView? = null
    private val readerHandler = Handler(Looper.getMainLooper())
    private var readerActive = false
    private var pendingBackupExport: MethodChannel.Result? = null
    private var pendingBackupSourcePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starslibrary/reader_images",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> saveReaderImage(
                    sourcePath = call.argument<String>("path"),
                    fileName = call.argument<String>("fileName"),
                    mimeType = call.argument<String>("mimeType"),
                    result = result,
                )
                "shareImage" -> shareReaderImage(
                    sourcePath = call.argument<String>("path"),
                    fileName = call.argument<String>("fileName"),
                    mimeType = call.argument<String>("mimeType"),
                    text = call.argument<String>("text"),
                    result = result,
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starslibrary/backup_files",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportBackup" -> exportBackupWithDocumentPicker(
                    sourcePath = call.argument<String>("sourcePath"),
                    fileName = call.argument<String>("fileName"),
                    result = result,
                )
                else -> result.notImplemented()
            }
        }
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
                "clearCookiesForUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("invalid_url", "A URL is required.", null)
                        return@setMethodCallHandler
                    }
                    val manager = CookieManager.getInstance()
                    manager.getCookie(url).orEmpty().split(';').forEach { pair ->
                        val name = pair.substringBefore('=').trim()
                        if (name.isNotEmpty()) {
                            manager.setCookie(url, "$name=; Max-Age=0; Path=/")
                        }
                    }
                    manager.flush()
                    result.success(null)
                }
                "loadHtml" -> loadHtmlInWebView(
                    url = call.argument<String>("url"),
                    userAgent = call.argument<String>("userAgent"),
                    readySelector = call.argument<String>("readySelector"),
                    autoScroll = call.argument<Boolean>("autoScroll") ?: false,
                    renderedViewport = call.argument<Boolean>("renderedViewport") ?: false,
                    sanitizeHtml = call.argument<Boolean>("sanitizeHtml") ?: false,
                    clickSelector = call.argument<String>("clickSelector"),
                    maxClicks = call.argument<Int>("maxClicks") ?: 0,
                    result = result,
                )
                "loadImage" -> loadImageInWebView(
                    url = call.argument<String>("url"),
                    userAgent = call.argument<String>("userAgent"),
                    result = result,
                )
                "composeReaderImage" -> composeReaderImage(
                    slices = call.argument<List<ByteArray>>("slices"),
                    outputPath = call.argument<String>("outputPath"),
                    result = result,
                )
                "loadBytes" -> loadBytesInWebView(
                    url = call.argument<String>("url"),
                    headers = call.argument<Map<String, String>>("headers"),
                    method = call.argument<String>("method"),
                    body = call.argument<String>("body"),
                    result = result,
                )
                else -> result.notImplemented()
            }
        }

        // Streams reader page file paths one at a time as they are extracted,
        // so the Dart reader can render progressively instead of waiting for the
        // whole chapter.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "starslibrary/reader_pages",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val args = arguments as? Map<*, *>
                if (args?.get("mode") == "lazyUrls") {
                    startLazyReaderUrlStream(
                        url = args["url"] as? String,
                        userAgent = args["userAgent"] as? String,
                        events = events,
                    )
                } else {
                    startReaderStream(
                        url = args?.get("url") as? String,
                        userAgent = args?.get("userAgent") as? String,
                        pageCount = (args?.get("pageCount") as? Int) ?: 0,
                        events = events,
                    )
                }
            }

            override fun onCancel(arguments: Any?) {
                stopReaderStream()
            }
        })
    }

    private fun saveReaderImage(
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        result: MethodChannel.Result,
    ) {
        val source = sourcePath?.let(::File)
        if (source == null || !source.isFile || fileName.isNullOrBlank()) {
            result.error("invalid_image", "The reader image file is unavailable.", null)
            return
        }
        try {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType ?: "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/StarsLibrary",
                    )
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val uri = contentResolver.insert(collection, values)
                ?: throw IllegalStateException("Android could not create the gallery item.")
            try {
                contentResolver.openOutputStream(uri, "w")?.use { output ->
                    source.inputStream().use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("Android could not open the gallery item.")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                }
            } catch (error: Exception) {
                contentResolver.delete(uri, null, null)
                throw error
            }
            result.success("Pictures/StarsLibrary/$fileName")
        } catch (error: Exception) {
            result.error("save_failed", error.message ?: "Could not save image.", null)
        }
    }

    private fun exportBackupWithDocumentPicker(
        sourcePath: String?,
        fileName: String?,
        result: MethodChannel.Result,
    ) {
        if (sourcePath.isNullOrBlank() || !File(sourcePath).isFile) {
            result.error("missing_backup", "The backup file no longer exists.", null)
            return
        }
        if (pendingBackupExport != null) {
            result.error("export_in_progress", "Another backup export is already open.", null)
            return
        }

        pendingBackupExport = result
        pendingBackupSourcePath = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, fileName ?: File(sourcePath).name)
        }
        try {
            startActivityForResult(intent, CREATE_BACKUP_DOCUMENT_REQUEST)
        } catch (error: Exception) {
            pendingBackupExport = null
            pendingBackupSourcePath = null
            result.error("picker_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated in Android, retained for the Flutter activity result bridge.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CREATE_BACKUP_DOCUMENT_REQUEST) return

        val result = pendingBackupExport
        val sourcePath = pendingBackupSourcePath
        pendingBackupExport = null
        pendingBackupSourcePath = null

        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val destination = data.data!!
        try {
            contentResolver.openOutputStream(destination, "w").use { output ->
                requireNotNull(output) { "The selected destination could not be opened." }
                File(sourcePath!!).inputStream().use { input -> input.copyTo(output) }
            }
            result.success(destination.toString())
        } catch (error: Exception) {
            result.error("export_failed", error.message, null)
        }
    }

    private fun shareReaderImage(
        sourcePath: String?,
        fileName: String?,
        mimeType: String?,
        text: String?,
        result: MethodChannel.Result,
    ) {
        val source = sourcePath?.let(::File)
        if (source == null || !source.isFile || fileName.isNullOrBlank()) {
            result.error("invalid_image", "The reader image file is unavailable.", null)
            return
        }
        try {
            val shareDirectory = File(cacheDir, "reader_shared_images").apply {
                mkdirs()
            }
            shareDirectory.listFiles()?.forEach { oldFile ->
                if (oldFile.name != fileName) oldFile.delete()
            }
            val sharedFile = File(shareDirectory, fileName)
            source.copyTo(sharedFile, overwrite = true)
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.reader_images",
                sharedFile,
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType ?: "image/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!text.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, text)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = android.content.ClipData.newRawUri(fileName, uri)
            }
            startActivity(Intent.createChooser(intent, "Share image"))
            result.success(null)
        } catch (error: Exception) {
            result.error("share_failed", error.message ?: "Could not share image.", null)
        }
    }

    /**
     * Loads protected API/binary responses through Chromium itself. LuraToons
     * rejects the TLS/network fingerprint of a plain HttpURLConnection even
     * when its session cookie is valid; executing fetch from a same-origin
     * WebView keeps the exact cookie jar and browser fingerprint established by
     * the OAuth flow. Bytes are transferred in bounded chunks to avoid the
     * evaluateJavascript return-size limit.
     */
    private fun loadBytesInWebView(
        url: String?,
        headers: Map<String, String>?,
        method: String?,
        body: String?,
        result: MethodChannel.Result,
    ) {
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "A URL is required.", null)
            return
        }
        val target = try {
            URL(url)
        } catch (error: Exception) {
            result.error("invalid_url", error.message, null)
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
        headers.orEmpty().entries
            .firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
            ?.value
            ?.takeIf { it.isNotBlank() }
            ?.let { webView.settings.userAgentString = it }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        CookieManager.getInstance().flush()

        val finished = AtomicBoolean(false)
        val fetchStarted = AtomicBoolean(false)
        val output = ByteArrayOutputStream()
        val responseHeaders = linkedMapOf<String, String>()
        var statusCode = 0

        fun dispose() {
            handler.removeCallbacksAndMessages(null)
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.removeJavascriptInterface("StarsBinary")
            webView.stopLoading()
            webView.destroy()
        }
        fun fail(code: String, message: String) {
            if (!finished.compareAndSet(false, true)) return
            handler.post {
                result.error(code, message, null)
                dispose()
            }
        }
        fun succeed() {
            if (!finished.compareAndSet(false, true)) return
            val body = synchronized(output) { output.toByteArray() }
            val headersSnapshot = synchronized(responseHeaders) {
                responseHeaders.toMap()
            }
            handler.post {
                result.success(
                    mapOf(
                        "statusCode" to statusCode,
                        "body" to body,
                        "headers" to headersSnapshot,
                    ),
                )
                dispose()
            }
        }

        class BinaryBridge {
            @JavascriptInterface
            fun begin(status: Int, rawHeaders: String) {
                statusCode = status
                try {
                    val parsed = JSONObject(rawHeaders)
                    synchronized(responseHeaders) {
                        parsed.keys().forEach { name ->
                            responseHeaders[name.lowercase()] = parsed.optString(name)
                        }
                    }
                } catch (_: Exception) {
                }
            }

            @JavascriptInterface
            fun chunk(encoded: String) {
                try {
                    val bytes = Base64.decode(encoded, Base64.DEFAULT)
                    synchronized(output) { output.write(bytes) }
                } catch (error: Exception) {
                    fail("binary_decode_failed", error.message ?: "Could not decode response bytes.")
                }
            }

            @JavascriptInterface
            fun complete() = succeed()

            @JavascriptInterface
            fun failure(message: String) = fail("binary_load_failed", message)
        }
        webView.addJavascriptInterface(BinaryBridge(), "StarsBinary")

        val allowedHeaders = headers.orEmpty().filterKeys { name ->
            !name.equals("Cookie", ignoreCase = true) &&
                !name.equals("User-Agent", ignoreCase = true) &&
                !name.equals("Referer", ignoreCase = true) &&
                !name.equals("Accept-Encoding", ignoreCase = true)
        }
        val requestHeaders = JSONObject(allowedHeaders).toString()
        val requestMethod = method.orEmpty().uppercase().ifBlank { "GET" }
        if (requestMethod !in setOf("GET", "POST")) {
            result.error("invalid_method", "Only GET and POST are supported.", null)
            dispose()
            return
        }
        val script = """
            (async function() {
              try {
                const method = ${JSONObject.quote(requestMethod)};
                const headers = $requestHeaders;
                if (method !== 'GET' && !headers['X-CSRFToken']) {
                  const match = document.cookie.match(/(?:^|;\s*)csrftoken=([^;]+)/);
                  if (match) headers['X-CSRFToken'] = decodeURIComponent(match[1]);
                }
                const response = await fetch(${JSONObject.quote(url)}, {
                  method,
                  credentials: 'include',
                  cache: 'no-store',
                  headers,
                  ${if (requestMethod == "GET") "" else "body: ${JSONObject.quote(body ?: "")},"}
                });
                const responseHeaders = {};
                response.headers.forEach((value, name) => {
                  responseHeaders[name] = value;
                });
                StarsBinary.begin(response.status, JSON.stringify(responseHeaders));
                const bytes = new Uint8Array(await response.arrayBuffer());
                const chunkSize = 32768;
                for (let offset = 0; offset < bytes.length; offset += chunkSize) {
                  const end = Math.min(offset + chunkSize, bytes.length);
                  let binary = '';
                  for (let index = offset; index < end; index++) {
                    binary += String.fromCharCode(bytes[index]);
                  }
                  StarsBinary.chunk(btoa(binary));
                }
                StarsBinary.complete();
              } catch (error) {
                StarsBinary.failure(String((error && error.message) || error));
              }
            })();
        """.trimIndent()

        handler.postDelayed(
            { fail("binary_timeout", "The authenticated browser request timed out.") },
            120_000,
        )
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                if (finished.get() || !fetchStarted.compareAndSet(false, true)) return
                handler.postDelayed({
                    if (!finished.get()) webView.evaluateJavascript(script, null)
                }, 350)
            }
        }
        val origin = "${target.protocol}://${target.authority}/"
        webView.loadUrl(origin)
    }

    private fun composeReaderImage(
        slices: List<ByteArray>?,
        outputPath: String?,
        result: MethodChannel.Result,
    ) {
        if (slices.isNullOrEmpty() || outputPath.isNullOrBlank()) {
            result.error("invalid_page", "Image slices and output path are required.", null)
            return
        }
        Thread {
            val bitmaps = mutableListOf<Bitmap>()
            var joined: Bitmap? = null
            try {
                slices.forEachIndexed { index, bytes ->
                    val bitmap = decodeReaderSlice(bytes)
                        ?: error("Android could not decode image slice ${index + 1}.")
                    bitmaps.add(bitmap)
                }
                val width = bitmaps.maxOf { it.width }
                val height = bitmaps.sumOf { it.height }
                require(width > 0 && height > 0) { "The composed page has invalid dimensions." }
                val output = File(outputPath)
                output.parentFile?.mkdirs()

                // Flutter's ordinary Image widget cannot reliably upload very
                // tall bitmaps as one GPU texture. A 30k-pixel webtoon page is
                // silently squeezed vertically on affected devices. Compose
                // it into texture-safe consecutive tiles instead; the webtoon
                // ListView renders them without spacing, preserving scale.
                val outputPaths = mutableListOf<String>()
                var sourceBitmapIndex = 0
                var sourceY = 0
                var remainingHeight = height
                var tileIndex = 0
                while (remainingHeight > 0) {
                    val tileHeight = minOf(MAX_READER_TILE_HEIGHT, remainingHeight)
                    joined = Bitmap.createBitmap(width, tileHeight, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(joined!!)
                    canvas.drawColor(Color.BLACK)
                    var tileY = 0
                    while (tileY < tileHeight && sourceBitmapIndex < bitmaps.size) {
                        val bitmap = bitmaps[sourceBitmapIndex]
                        val available = bitmap.height - sourceY
                        val copyHeight = minOf(available, tileHeight - tileY)
                        val source = Rect(0, sourceY, bitmap.width, sourceY + copyHeight)
                        val destination = Rect(0, tileY, bitmap.width, tileY + copyHeight)
                        canvas.drawBitmap(bitmap, source, destination, null)
                        tileY += copyHeight
                        sourceY += copyHeight
                        if (sourceY == bitmap.height) {
                            sourceBitmapIndex++
                            sourceY = 0
                        }
                    }

                    val tileOutput = if (height <= MAX_READER_TILE_HEIGHT) {
                        output
                    } else {
                        File(
                            output.parentFile,
                            "${output.nameWithoutExtension}-${tileIndex.toString().padStart(3, '0')}.jpg",
                        )
                    }
                    FileOutputStream(tileOutput).use { stream ->
                        check(joined!!.compress(Bitmap.CompressFormat.JPEG, 90, stream)) {
                            "Android could not encode reader tile ${tileIndex + 1}."
                        }
                    }
                    outputPaths.add(tileOutput.absolutePath)
                    joined!!.recycle()
                    joined = null
                    remainingHeight -= tileHeight
                    tileIndex++
                }
                runOnUiThread { result.success(outputPaths) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("image_compose_failed", error.message, null)
                }
            } finally {
                bitmaps.forEach { it.recycle() }
                joined?.recycle()
            }
        }.start()
    }

    private fun decodeReaderSlice(bytes: ByteArray): Bitmap? {
        try {
            val decoder = tachiyomi.decoder.ImageDecoder.newInstance(
                ByteArrayInputStream(bytes),
            )
            if (decoder != null) {
                try {
                    val bounds = android.graphics.Rect(0, 0, decoder.width, decoder.height)
                    decoder.decode(bounds)?.let { return it }
                } finally {
                    decoder.recycle()
                }
            }
        } catch (_: Throwable) {
            // Continue with platform decoders for ordinary formats.
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            try {
                val source = ImageDecoder.createSource(ByteBuffer.wrap(bytes))
                return ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                    // The result is drawn onto a software Canvas below. A
                    // hardware bitmap cannot be used as that Canvas' source.
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                }
            } catch (_: Throwable) {
                // Some legacy PNG/WebP slices are accepted by BitmapFactory
                // even when ImageDecoder rejects their metadata.
            }
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }

    companion object {
        private const val CREATE_BACKUP_DOCUMENT_REQUEST = 4107
        private const val MAX_READER_TILE_HEIGHT = 8192
    }

    private fun loadHtmlInWebView(
        url: String?,
        userAgent: String?,
        readySelector: String?,
        autoScroll: Boolean,
        renderedViewport: Boolean,
        sanitizeHtml: Boolean,
        clickSelector: String?,
        maxClicks: Int,
        result: MethodChannel.Result,
    ) {
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "A URL is required.", null)
            return
        }
        Log.v(
            "StarsHtmlLoader",
            "start url=$url selector=$readySelector autoScroll=$autoScroll renderedViewport=$renderedViewport sanitizeHtml=$sanitizeHtml",
        )
        val handler = Handler(Looper.getMainLooper())
        val webView = WebView(this)
        // Lazy readers size placeholders from the viewport and commonly use
        // IntersectionObserver to materialize the next image. A 1x1 WebView
        // collapses those placeholders and may expose only the first batch.
        val viewportWidth = if (autoScroll || renderedViewport) {
            resources.displayMetrics.widthPixels.coerceAtLeast(360)
        } else {
            1
        }
        val viewportHeight = if (autoScroll || renderedViewport) {
            resources.displayMetrics.heightPixels.coerceAtLeast(640)
        } else {
            1
        }
        val layoutParams = FrameLayout.LayoutParams(viewportWidth, viewportHeight)
        webView.alpha = 0.01f
        webView.translationX = -(viewportWidth * 2).toFloat()
        webView.translationY = -(viewportHeight * 2).toFloat()
        addContentView(webView, layoutParams)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        if (!userAgent.isNullOrBlank()) webView.settings.userAgentString = userAgent
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        CookieManager.getInstance().flush()

        var finished = false
        var snapshotting = false
        fun dispose() {
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.stopLoading()
            webView.destroy()
        }
        fun finishWithHtml() {
            if (finished || snapshotting) return
            snapshotting = true
            val snapshotScript = if (sanitizeHtml) {
                """
                (() => {
                  const fragments = [];
                  const seen = new Set();
                  document.querySelectorAll('a[href*="/manga/"]').forEach(anchor => {
                    const href = anchor.href || anchor.getAttribute('href') || '';
                    if (!href || seen.has(href)) return;
                    const title = (anchor.textContent || '').trim() ||
                      anchor.getAttribute('aria-label') ||
                      anchor.getAttribute('title') || href.split('/').filter(Boolean).pop();
                    const image = anchor.parentElement && anchor.parentElement.querySelector('img');
                    const source = anchor.parentElement &&
                      (anchor.parentElement.querySelector('source[type="image/webp"][srcset]') ||
                        anchor.parentElement.querySelector('source[srcset]'));
                    const sourceCover = source && (source.getAttribute('srcset') || '')
                      .split(',')[0].trim().split(/\s+/)[0];
                    const rawCover = image && (
                      image.getAttribute('data-src') ||
                      image.getAttribute('data-lazy-src') ||
                      image.getAttribute('src') || ''
                    );
                    const cover = sourceCover ||
                      (rawCover && !rawCover.startsWith('data:') ? rawCover : '');
                    const card = (anchor.parentElement && anchor.parentElement.parentElement) ||
                      anchor.parentElement || anchor;
                    const cardText = (card.textContent || '').replace(/\s+/g, ' ').trim();
                    fragments.push(
                      '<article><a href="' + href + '">' + title +
                      (cover ? '<img src="' + cover + '">' : '') +
                      '</a><span>' + cardText + '</span></article>'
                    );
                    seen.add(href);
                  });
                  return '<html><body>' + fragments.join('') + '</body></html>';
                })()
                """.trimIndent()
            } else {
                "document.documentElement.outerHTML"
            }
            webView.evaluateJavascript(snapshotScript) { html ->
                if (finished) return@evaluateJavascript
                val mangaLinks = Regex("/manga/").findAll(html ?: "").count()
                Log.v(
                    "StarsHtmlLoader",
                    "finish url=${webView.url} htmlChars=${html?.length ?: 0} mangaLinks=$mangaLinks",
                )
                finished = true
                result.success(html ?: "")
                dispose()
            }
        }
        fun scrollLazyContent() {
            webView.evaluateJavascript(
                """
                (() => {
                  if (window.__starsLazyWalkStarted) return;
                  window.__starsLazyWalkStarted = true;
                  window.__starsLazyWalkDone = false;
                  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
                  (async () => {
                    const slotSelector =
                      'main > div:first-child > div.w-full.flex.justify-center';
                    const loadedReaderImages = () => Array.from(
                      document.querySelectorAll(slotSelector + ' img[alt^="Página"]')
                    ).filter(image => image.currentSrc || image.getAttribute('src')).length;
                    let readerSlots = Array.from(document.querySelectorAll(slotSelector));
                    if (readerSlots.length > 0) {
                      // React replaces each placeholder as it enters the
                      // observer area, so re-query on every step instead of
                      // walking a stale NodeList captured before lazy loading.
                      for (let pass = 0; pass < 4; pass++) {
                        readerSlots = Array.from(document.querySelectorAll(slotSelector));
                        for (let index = 0; index < readerSlots.length; index++) {
                          const liveSlots = Array.from(
                            document.querySelectorAll(slotSelector)
                          );
                          const slot = liveSlots[index];
                          if (!slot) continue;
                          const image = slot.querySelector('img[alt^="Página"]');
                          if (image && (image.currentSrc || image.getAttribute('src'))) {
                            continue;
                          }
                          slot.scrollIntoView({block: 'center'});
                          await sleep(550);
                        }
                        const expected = document.querySelectorAll(slotSelector).length;
                        if (expected > 0 && loadedReaderImages() >= expected) break;
                      }
                    } else {
                      let previousHeight = 0;
                      let stable = 0;
                      while (stable < 3) {
                        window.scrollBy(0, Math.max(window.innerHeight * 0.8, 600));
                        await sleep(350);
                        const height = document.documentElement.scrollHeight;
                        stable = height === previousHeight &&
                          window.scrollY + window.innerHeight >= height - 8
                            ? stable + 1
                            : 0;
                        previousHeight = height;
                      }
                    }
                    // Give the final observer callbacks and React render a
                    // chance to replace the last placeholders before taking
                    // the DOM snapshot.
                    await sleep(1200);
                    window.scrollTo(0, 0);
                    window.__starsLazyWalkDone = true;
                  })().catch(() => { window.__starsLazyWalkDone = true; });
                })()
                """.trimIndent(),
            ) { }
        }
        fun clickProgressiveContent(onDone: () -> Unit) {
            if (clickSelector.isNullOrBlank() || maxClicks <= 0) {
                onDone()
                return
            }
            val quotedSelector = JSONObject.quote(clickSelector)
            var clicks = 0
            fun clickNext() {
                if (finished || clicks >= maxClicks) {
                    onDone()
                    return
                }
                webView.evaluateJavascript(
                    """
                    (() => {
                      const element = document.querySelector($quotedSelector);
                      if (!element || element.disabled) return 'missing';
                      if (element.hasAttribute('data-loading') ||
                          element.hasAttribute('data-flux-loading')) {
                        return 'loading';
                      }
                      element.click();
                      return 'clicked';
                    })()
                    """.trimIndent(),
                ) { state ->
                    if (state == "\"loading\"") {
                        handler.postDelayed({ clickNext() }, 400)
                    } else if (state == "\"clicked\"") {
                        clicks += 1
                        handler.postDelayed({ clickNext() }, 1_200)
                    } else {
                        onDone()
                    }
                }
            }
            clickNext()
        }
        fun probe() {
            if (finished) return
            val selector = JSONObject.quote(readySelector ?: "main, body")
            webView.evaluateJavascript(
                "Boolean(document.querySelector($selector))",
            ) { ready ->
                if (finished) return@evaluateJavascript
                Log.v("StarsHtmlLoader", "probe url=${webView.url} ready=$ready selector=$readySelector")
                if (ready == "true") {
                    if (!autoScroll) {
                        clickProgressiveContent {
                            handler.postDelayed({ finishWithHtml() }, 700)
                        }
                    } else {
                        scrollLazyContent()
                        fun waitForScroll() {
                            if (finished) return
                            webView.evaluateJavascript(
                                "Boolean(window.__starsLazyWalkDone)",
                            ) { done ->
                                if (done == "true") finishWithHtml()
                                else handler.postDelayed({ waitForScroll() }, 400)
                            }
                        }
                        handler.postDelayed({ waitForScroll() }, 500)
                    }
                } else handler.postDelayed({ probe() }, 500)
            }
        }

        val timeout = Runnable { finishWithHtml() }
        handler.postDelayed(timeout, if (autoScroll) 60_000 else 20_000)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                Log.v("StarsHtmlLoader", "pageFinished url=$loadedUrl")
                handler.postDelayed({ probe() }, 350)
            }
        }
        webView.loadUrl(url)
    }

    private fun loadImageInWebView(
        url: String?,
        userAgent: String?,
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
        fun fail(code: String, message: String) {
            if (finished) return
            finished = true
            result.error(code, message, null)
            dispose()
        }
        fun probe() {
            if (finished) return
            webView.evaluateJavascript(
                """
                (() => {
                  const image = document.querySelector('img');
                  if (!image || !image.complete || !image.naturalWidth) return null;
                  const canvas = document.createElement('canvas');
                  canvas.width = image.naturalWidth;
                  canvas.height = image.naturalHeight;
                  canvas.getContext('2d').drawImage(image, 0, 0);
                  return canvas.toDataURL('image/png').split(',', 2)[1];
                })()
                """.trimIndent(),
            ) { encoded ->
                if (finished) return@evaluateJavascript
                if (encoded == null || encoded == "null") {
                    handler.postDelayed({ probe() }, 300)
                    return@evaluateJavascript
                }
                try {
                    val base64 = JSONObject("{\"value\":$encoded}").getString("value")
                    val bytes = Base64.decode(base64, Base64.DEFAULT)
                    if (bytes.isEmpty()) {
                        fail("empty_image", "The browser returned an empty image.")
                    } else {
                        finished = true
                        result.success(bytes)
                        dispose()
                    }
                } catch (error: Exception) {
                    fail("image_decode_failed", error.message ?: "Could not decode image.")
                }
            }
        }

        handler.postDelayed(
            { fail("image_timeout", "The browser image request timed out.") },
            20_000,
        )
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                handler.postDelayed({ probe() }, 250)
            }
        }
        webView.loadUrl(url)
    }

    /** Tears down any in-flight reader WebView and cancels its pending work. */
    private fun stopReaderStream() {
        readerActive = false
        readerHandler.removeCallbacksAndMessages(null)
        val webView = readerWebView
        readerWebView = null
        if (webView != null) {
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.stopLoading()
            webView.destroy()
        }
    }

    /**
     * Walks a slot-based lazy reader and emits each remote image URL as soon
     * as the frontend attaches it. The Dart side can therefore render the
     * first pages while this offscreen WebView keeps materializing the rest.
     */
    private fun startLazyReaderUrlStream(
        url: String?,
        userAgent: String?,
        events: EventChannel.EventSink?,
    ) {
        if (events == null) return
        if (url.isNullOrBlank()) {
            events.error("invalid_url", "A URL is required.", null)
            events.endOfStream()
            return
        }
        stopReaderStream()
        readerActive = true

        val webView = WebView(this)
        readerWebView = webView
        val viewportWidth = resources.displayMetrics.widthPixels.coerceAtLeast(360)
        val viewportHeight = resources.displayMetrics.heightPixels.coerceAtLeast(640)
        val layoutParams = FrameLayout.LayoutParams(viewportWidth, viewportHeight)
        webView.alpha = 0.01f
        webView.translationX = -(viewportWidth * 2).toFloat()
        webView.translationY = -(viewportHeight * 2).toFloat()
        addContentView(webView, layoutParams)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.loadsImagesAutomatically = true
        if (!userAgent.isNullOrBlank()) webView.settings.userAgentString = userAgent
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        CookieManager.getInstance().flush()

        var emitted = 0
        fun finish() {
            if (!readerActive) return
            readerActive = false
            events.endOfStream()
            stopReaderStream()
        }
        readerHandler.postDelayed({ finish() }, 120_000L)

        val driver = """
            (function(){
              if (window.__starsLazyReader) return;
              var state = window.__starsLazyReader = {
                urls: [], drained: 0, expected: 0, done: false, error: null
              };
              var selector =
                'main > div:first-child > div.w-full.flex.justify-center';
              function sleep(ms){
                return new Promise(function(resolve){ setTimeout(resolve, ms); });
              }
              function imageUrl(slot){
                var image = slot && slot.querySelector('img[alt^="Página"]');
                return image && (image.currentSrc || image.getAttribute('src'));
              }
              function capture(){
                var slots = Array.from(document.querySelectorAll(selector));
                state.expected = Math.max(state.expected, slots.length);
                slots.forEach(function(slot, index){
                  var src = imageUrl(slot);
                  if (src && !state.urls[index]) state.urls[index] = src;
                });
                return slots;
              }
              function waitForSlots(){
                var started = Date.now();
                return (function check(){
                  var slots = capture();
                  if (slots.length) return Promise.resolve(slots);
                  if (Date.now() - started > 25000) return Promise.resolve([]);
                  return sleep(250).then(check);
                })();
              }
              function materialize(index){
                var attempts = 0;
                return (function check(){
                  var slots = capture();
                  if (state.urls[index]) return Promise.resolve(true);
                  var slot = slots[index];
                  if (!slot || attempts++ >= 32) return Promise.resolve(false);
                  slot.scrollIntoView({block: 'center'});
                  return sleep(250).then(check);
                })();
              }
              waitForSlots().then(function(slots){
                if (!slots.length) throw new Error('Reader slots were not found.');
                var pass = 0;
                return (function walk(){
                  capture();
                  var index = 0;
                  return (function next(){
                    var current = capture();
                    if (index >= current.length) return Promise.resolve();
                    var target = index++;
                    return materialize(target).then(next);
                  })().then(function(){
                    capture();
                    var complete = state.expected > 0;
                    for (var i = 0; i < state.expected; i++) {
                      if (!state.urls[i]) { complete = false; break; }
                    }
                    if (complete || ++pass >= 4) return;
                    return sleep(600).then(walk);
                  });
                })();
              }).then(function(){
                window.scrollTo(0, 0);
                state.done = true;
              }).catch(function(error){
                state.error = String((error && error.message) || error);
                state.done = true;
              });
            })();
        """.trimIndent()

        val drainJs = """
            (function(){
              var state = window.__starsLazyReader;
              if (!state) return JSON.stringify({ready:false});
              var url = state.urls[state.drained];
              if (url) {
                state.urls[state.drained] = null;
                state.drained += 1;
                return JSON.stringify({ready:true, url:url, done:state.done});
              }
              return JSON.stringify({
                ready:true, url:null, done:state.done, error:state.error,
                loaded:state.drained, expected:state.expected
              });
            })()
        """.trimIndent()

        fun poll() {
            if (!readerActive) return
            val view = readerWebView ?: return
            view.evaluateJavascript(drainJs) { encoded ->
                if (!readerActive) return@evaluateJavascript
                val payload = try {
                    if (encoded == null || encoded == "null") null
                    else JSONObject(JSONObject("{\"v\":$encoded}").getString("v"))
                } catch (_: Exception) {
                    null
                }
                if (payload == null) {
                    readerHandler.postDelayed({ poll() }, 200)
                    return@evaluateJavascript
                }
                val pageUrl = if (payload.isNull("url")) null else payload.optString("url")
                if (!pageUrl.isNullOrBlank()) {
                    emitted += 1
                    events.success(pageUrl)
                    readerHandler.post { poll() }
                } else if (payload.optBoolean("done", false)) {
                    if (emitted == 0 && payload.has("error")) {
                        events.error(
                            "reader_failed",
                            payload.optString("error", "The reader exposed no pages."),
                            null,
                        )
                    }
                    finish()
                } else {
                    readerHandler.postDelayed({ poll() }, 200)
                }
            }
        }

        var polling = false
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                if (!readerActive) return
                webView.evaluateJavascript(driver, null)
                if (!polling) {
                    polling = true
                    readerHandler.postDelayed({ poll() }, 350)
                }
            }
        }
        webView.loadUrl(url)
    }

    /**
     * Drives the HDoujin SPA reader inside an offscreen WebView (which clears
     * Cloudflare) and streams each page image as it becomes available.
     *
     * A JS "driver" accumulates each page as a data URL into `window.__hd`,
     * handling both the continuous (all imgs in the DOM) and paged (one img,
     * click Next) layouts. The native side polls `window.__hd`, drains one page
     * at a time, decodes it, writes it under
     * `cacheDir/hdoujin_reader/<timestamp>/NNNN.<ext>` and emits the absolute
     * path through the event sink. The stream ends when the driver is done or
     * the overall timeout fires (whatever was collected is kept).
     */
    private fun startReaderStream(
        url: String?,
        userAgent: String?,
        pageCount: Int,
        events: EventChannel.EventSink?,
    ) {
        if (events == null) return
        if (url.isNullOrBlank()) {
            events.error("invalid_url", "A URL is required.", null)
            events.endOfStream()
            return
        }
        // Only one reader stream at a time.
        stopReaderStream()
        readerActive = true

        val webView = WebView(this)
        readerWebView = webView
        // A real-ish offscreen viewport so the reader lays out and can advance.
        val layoutParams = FrameLayout.LayoutParams(1080, 1920)
        webView.alpha = 0.01f
        webView.translationX = -2000f
        webView.translationY = -2000f
        addContentView(webView, layoutParams)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.loadsImagesAutomatically = true
        if (!userAgent.isNullOrBlank()) webView.settings.userAgentString = userAgent
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        CookieManager.getInstance().flush()

        val outputDir = File(
            File(cacheDir, "hdoujin_reader"),
            System.currentTimeMillis().toString(),
        )
        outputDir.mkdirs()
        var written = 0

        fun finish() {
            if (!readerActive) return
            readerActive = false
            events.endOfStream()
            stopReaderStream()
        }

        val overallTimeout = (maxOf(pageCount, 1).toLong() * 6_000L + 20_000L)
            .coerceAtMost(600_000L)
        readerHandler.postDelayed({ finish() }, overallTimeout)

        // Injected once per document; re-injecting is a no-op (guarded below).
        val driver = """
            (function(){
              if (window.__hd) return;
              window.__hd = {pages:[], drained:0, done:false, error:null, mode:null};
              var PAGE_COUNT = $pageCount;
              function ready(img){
                return img && img.src && img.src.indexOf('blob:')===0 &&
                  img.complete && img.naturalWidth>0;
              }
              function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }
              function toData(img){
                return fetch(img.src).then(function(r){ return r.blob(); })
                  .then(function(b){
                    return new Promise(function(res, rej){
                      var fr = new FileReader();
                      fr.onload = function(){ res(fr.result); };
                      fr.onerror = function(){ rej(fr.error); };
                      fr.readAsDataURL(b);
                    });
                  })
                  .catch(function(){
                    try {
                      var c = document.createElement('canvas');
                      c.width = img.naturalWidth; c.height = img.naturalHeight;
                      c.getContext('2d').drawImage(img, 0, 0);
                      return c.toDataURL('image/jpeg', 0.92);
                    } catch (e) { return null; }
                  });
              }
              function waitFor(get, timeoutMs){
                var start = Date.now();
                return (function loop(){
                  var el = get();
                  if (el) return Promise.resolve(el);
                  if (Date.now()-start >= timeoutMs) return Promise.resolve(null);
                  return sleep(200).then(loop);
                })();
              }
              function run(){
                return waitFor(function(){
                  var el = document.querySelector('#reader img[src^="blob:"]');
                  return ready(el) ? el : null;
                }, 25000).then(function(){
                  var all = document.querySelectorAll('#reader img[src^="blob:"]');
                  if (all.length >= 2) {
                    window.__hd.mode = 'continuous';
                    var i = 0;
                    return (function step(){
                      if (i >= all.length) return;
                      var img = all[i];
                      return waitFor(function(){ return ready(img) ? img : null; }, 25000)
                        .then(function(r){ return r ? toData(img) : null; })
                        .then(function(data){
                          if (data) window.__hd.pages.push(data);
                          i++;
                          return step();
                        });
                    })();
                  }
                  window.__hd.mode = 'paged';
                  var count = PAGE_COUNT > 0 ? PAGE_COUNT : 1;
                  var prev = null;
                  var n = 0;
                  return (function step(){
                    if (n >= count) return;
                    return waitFor(function(){
                      var el = document.querySelector('#reader img[src^="blob:"]');
                      return (el && el.src !== prev && ready(el)) ? el : null;
                    }, 25000).then(function(img){
                      if (!img) return;
                      prev = img.src;
                      return toData(img).then(function(data){
                        if (data) window.__hd.pages.push(data);
                        n++;
                        if (n >= count) return;
                        var next = document.querySelector('#reader nav button[title="Next"]');
                        if (!next) return;
                        next.click();
                        return sleep(400).then(step);
                      });
                    });
                  })();
                });
              }
              run().then(function(){ window.__hd.done = true; })
                .catch(function(e){
                  window.__hd.error = String((e && e.message) || e);
                  window.__hd.done = true;
                });
            })();
        """.trimIndent()

        val drainJs = """
            (function(){
              if (!window.__hd) return JSON.stringify({ready:false});
              var hd = window.__hd;
              if (hd.drained < hd.pages.length) {
                var item = hd.pages[hd.drained];
                hd.pages[hd.drained] = null;
                hd.drained += 1;
                return JSON.stringify({ready:true, page:item, done:hd.done, error:hd.error});
              }
              return JSON.stringify({ready:true, page:null, done:hd.done, error:hd.error});
            })()
        """.trimIndent()

        fun writeAndEmit(dataUrl: String) {
            val comma = dataUrl.indexOf(',')
            if (comma < 0) return
            val meta = dataUrl.substring(0, comma)
            val base64 = dataUrl.substring(comma + 1)
            val ext = when {
                meta.contains("image/png") -> "png"
                meta.contains("image/webp") -> "webp"
                meta.contains("image/gif") -> "gif"
                else -> "jpg"
            }
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            if (bytes.isEmpty()) return
            val file = File(outputDir, "%04d.%s".format(written, ext))
            file.writeBytes(bytes)
            written += 1
            events.success(file.absolutePath)
        }

        fun poll() {
            if (!readerActive) return
            val view = readerWebView ?: return
            view.evaluateJavascript(drainJs) { encoded ->
                if (!readerActive) return@evaluateJavascript
                if (encoded == null || encoded == "null") {
                    readerHandler.postDelayed({ poll() }, 300)
                    return@evaluateJavascript
                }
                val payload = try {
                    JSONObject(JSONObject("{\"v\":$encoded}").getString("v"))
                } catch (error: Exception) {
                    null
                }
                if (payload == null) {
                    readerHandler.postDelayed({ poll() }, 300)
                    return@evaluateJavascript
                }
                val page = if (payload.isNull("page")) null else payload.optString("page")
                if (!page.isNullOrEmpty()) {
                    try { writeAndEmit(page) } catch (_: Exception) {}
                    // Keep draining immediately while pages are available.
                    readerHandler.post { poll() }
                    return@evaluateJavascript
                }
                if (payload.optBoolean("done", false)) {
                    finish()
                } else {
                    readerHandler.postDelayed({ poll() }, 300)
                }
            }
        }

        var polling = false
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, loadedUrl: String?) {
                if (!readerActive) return
                // Re-inject each document (e.g. after a Cloudflare reload); the
                // driver self-guards against double-injection.
                webView.evaluateJavascript(driver, null)
                if (!polling) {
                    polling = true
                    readerHandler.postDelayed({ poll() }, 800)
                }
            }
        }
        webView.loadUrl(url)
    }

}
