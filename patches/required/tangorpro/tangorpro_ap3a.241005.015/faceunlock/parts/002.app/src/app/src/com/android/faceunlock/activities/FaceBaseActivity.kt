package com.android.faceunlock.activities

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import com.android.faceunlock.R
import co.aospa.sense.util.Constants

abstract class FaceBaseActivity : Activity() {

    private var mLaunchedConfirmLock = false
    @JvmField
    protected var mToken: ByteArray? = null
    protected var mUserId = 0

    override fun onCreate(bundle: Bundle?) {
        super.onCreate(bundle)

        mToken = intent.getByteArrayExtra(Constants.EXTRA_KEY_CHALLENGE_TOKEN)
        if (bundle != null && mToken == null) {
            mLaunchedConfirmLock = bundle.getBoolean(Constants.EXTRA_KEY_LAUNCHED_CONFIRM)
            mToken = bundle.getByteArray(Constants.EXTRA_KEY_CHALLENGE_TOKEN)
            mUserId = bundle.getInt(Intent.EXTRA_USER_ID)
        }
    }

    override fun onSaveInstanceState(bundle: Bundle) {
        super.onSaveInstanceState(bundle)
        bundle.putBoolean(Constants.EXTRA_KEY_LAUNCHED_CONFIRM, mLaunchedConfirmLock)
        bundle.putByteArray(Constants.EXTRA_KEY_CHALLENGE_TOKEN, mToken)
    }

    protected fun parseIntent(intent: Intent) {
        intent.putExtra(Constants.EXTRA_KEY_CHALLENGE_TOKEN, mToken)
        intent.putExtra(Intent.EXTRA_USER_ID, mUserId)
    }

    open fun setHeaderText(res: Int) {
        val header = findViewById<TextView>(R.id.header_text) ?: return
        val current = getText(res)
        header.text = current
        title = current
    }

    open fun setDescriptionText(res: Int) {
        val desc = findViewById<TextView>(R.id.description_text) ?: return
        desc.text = getText(res)
    }
}
