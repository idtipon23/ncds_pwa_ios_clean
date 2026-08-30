package com.example.ncds_voice_app_vol1

import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 📍 หน่วงเวลา 5 วินาที รอให้ Flutter โหลดหน้าจอเสร็จก่อนค่อยพิมพ์รหัส
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                info.signatures?.forEach { signature ->
                    val md = MessageDigest.getInstance("SHA")
                    md.update(signature.toByteArray())
                    val hashKey = Base64.encodeToString(md.digest(), Base64.NO_WRAP)
                    
                    Log.e("LINE_HASH", "=======================================")
                    Log.e("LINE_HASH", "🔑 Hash Key ของคุณคือ: $hashKey")
                    Log.e("LINE_HASH", "=======================================")
                }
            } catch (e: Exception) {
                Log.e("LINE_HASH", "Error: ${e.message}")
            }
        }, 5000) // 5000 มิลลิวินาที = 5 วินาที
    }
}