package com.example.shikhito_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.TelephonyManager
import android.telephony.SubscriptionManager
import android.telephony.SubscriptionInfo
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "shikhito/device"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"getSimNumber" -> {
					try {
						val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
						if (ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_NUMBERS) != PackageManager.PERMISSION_GRANTED &&
							ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
							result.success(null)
						} else {
							var number: String? = tm.line1Number
							if (number.isNullOrEmpty()) {
								try {
									val subManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
									val subs: List<SubscriptionInfo>? = subManager.activeSubscriptionInfoList
									if (subs != null && subs.isNotEmpty()) {
										for (s in subs) {
											val n = s.number
											if (!n.isNullOrEmpty()) {
												number = n
												break
											}
										}
									}
								} catch (_: Exception) {
									// ignore
								}
							}
							result.success(number)
						}
					} catch (e: Exception) {
						result.success(null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}
}
