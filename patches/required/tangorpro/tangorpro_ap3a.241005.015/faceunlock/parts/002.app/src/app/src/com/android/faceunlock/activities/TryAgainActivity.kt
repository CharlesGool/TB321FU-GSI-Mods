package com.android.faceunlock.activities

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
import com.android.faceunlock.R


class TryAgainActivity : FaceBaseActivity() {

    override fun onCreate(bundle: Bundle?) {
        super.onCreate(bundle)

        setContentView(R.layout.face_enroll_try_again)
        setHeaderText(R.string.face_try_again_title)
        setDescriptionText(R.string.face_try_again_description)

        val tryAgainBtn = findViewById<Button>(R.id.btn_try_again)
        tryAgainBtn?.setOnClickListener { setTryAgainButton() }
        if (mToken == null) {
            tryAgainBtn?.visibility = View.INVISIBLE
        }
    }

    override fun onPause() {
        super.onPause()
        finish()
    }

    private fun setTryAgainButton() {
        val intent = Intent()
        intent.setClass(this@TryAgainActivity, EnrollActivity::class.java)
        parseIntent(intent)
        startActivity(intent)
        finish()
    }
}
