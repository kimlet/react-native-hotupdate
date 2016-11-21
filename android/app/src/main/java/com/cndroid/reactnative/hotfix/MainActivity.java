package com.cndroid.reactnative.hotfix;

import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Message;
import android.support.v7.app.AppCompatActivity;
import android.util.Log;
import android.widget.Toast;

import com.cndroid.reactnativehotfixlib.ReactNativeHotFix;

/**
 * Created by jinbangzhu on 10/11/2016.
 */

public class MainActivity extends AppCompatActivity {
    ReactNativeHotFix reactNativeHotFix;

    class MyHandler extends Handler {
        @Override
        public void handleMessage(Message msg) {
            super.handleMessage(msg);
            switch (msg.what) {
                case ReactNativeHotFix.CODE_FAIL:
                    Toast.makeText(getApplicationContext(), "fail", Toast.LENGTH_LONG).show();
                    break;
                case ReactNativeHotFix.CODE_SUCCESS:
                    Toast.makeText(getApplicationContext(), "success", Toast.LENGTH_LONG).show();
                    break;
            }
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        MyHandler handler = new MyHandler();


        setContentView(R.layout.main);

        String extraBundleRootPath = Environment.getExternalStorageDirectory().getPath() + "/remoteReact/";

        reactNativeHotFix = ReactNativeHotFix.create(this)
                .setExtraBundleRootPath(extraBundleRootPath)
                .setUpgradeUrl("http://127.0.0.1:8000/v0.0.1_v0.0.2.json")
                .setPatchUrl("http://127.0.0.1:8000/v0.0.1_v0.0.2")
                .setHandler(handler);

        reactNativeHotFix.start();

    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        reactNativeHotFix.stop();
        Log.d("main", "onDestroy");
    }
}
