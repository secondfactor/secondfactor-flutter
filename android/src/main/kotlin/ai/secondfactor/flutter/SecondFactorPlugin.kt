package ai.secondfactor.flutter

import android.app.Activity
import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.IBinder
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * The Android half of `SecondFactor.verify`: opens the hosted page in a Custom
 * Tab and answers with the App Link the page returns to.
 *
 * The Dart side has already checked the page URL and split the return URL into
 * a host and a path. The return arrives in `onNewIntent` of the Flutter
 * activity, which therefore needs `android:launchMode="singleTask"`. When the
 * activity comes back to the front without that intent, the user closed the
 * tab, and the call ends as `canceled`.
 */
class SecondFactorPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.NewIntentListener,
    Application.ActivityLifecycleCallbacks {

    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null

    /** The call waiting for the user to come back, with the URL it waits for. */
    private var pending: MethodChannel.Result? = null
    private var returnHost = ""
    private var returnPath = ""

    /** Whether our activity has left the front since the tab was opened. */
    private var leftForTab = false

    override fun onAttachedToEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutter.binaryMessenger, "ai.secondfactor/verify")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "verify") return result.notImplemented()
        val activity = binding?.activity
            ?: return result.error("couldNotStart", "There is no activity to open the page from.", null)

        // Only one verification at a time. A second call means the first is
        // no longer wanted, so it ends as if the user had closed the tab.
        finish { it.error("canceled", "Another verification was started.", null) }

        // The Custom Tabs protocol is a plain intent extra: a browser that
        // supports Custom Tabs opens the URL in one when this key is present,
        // even with a null value, and any other browser ignores it. Using the
        // key directly avoids a dependency on androidx.browser.
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))
            .putExtras(Bundle().apply { putBinder("android.support.customtabs.extra.SESSION", null as IBinder?) })
        try {
            activity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            return result.error("couldNotStart", "The device has no browser to open the page in.", null)
        }
        pending = result
        returnHost = call.argument<String>("host").orEmpty()
        returnPath = call.argument<String>("path").orEmpty()
        leftForTab = false
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val data = intent.data ?: return false
        if (pending == null || !isReturn(data)) return false
        val url = data.toString()
        // Removing the URL keeps it from being read again later in the
        // activity's life, and stops Flutter's own deep linking, which reads
        // the intent after the plugins do, from pushing it as a route.
        intent.data = null
        finish { it.success(url) }
        return true
    }

    override fun onActivityResumed(activity: Activity) {
        // onNewIntent always runs before onResume, so a return would already
        // have finished the call. Coming back without one means the user
        // closed the tab.
        if (activity === binding?.activity && leftForTab) {
            finish { it.error("canceled", "The user closed the page.", null) }
        }
    }

    override fun onActivityPaused(activity: Activity) {
        if (activity === binding?.activity && pending != null) leftForTab = true
    }

    /** Whether [uri] is the return URL: https, with the same host and path.
     * The path is compared as sent, still percent-encoded. */
    private fun isReturn(uri: Uri): Boolean =
        uri.scheme.equals("https", ignoreCase = true) &&
            uri.host.equals(returnHost, ignoreCase = true) &&
            (uri.encodedPath.takeUnless { it.isNullOrEmpty() } ?: "/") == returnPath

    /** Ends the pending call, if any, exactly once. */
    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        leftForTab = false
        answer(result)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addOnNewIntentListener(this)
        binding.activity.application.registerActivityLifecycleCallbacks(this)
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
        finish { it.error("canceled", "The activity went away before the user came back.", null) }
    }

    // A configuration change recreates the activity, and the user may still
    // come back to the new one, so the pending call is kept.
    override fun onDetachedFromActivityForConfigChanges() {
        binding?.let {
            it.removeOnNewIntentListener(this)
            it.activity.application.unregisterActivityLifecycleCallbacks(this)
        }
        binding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
