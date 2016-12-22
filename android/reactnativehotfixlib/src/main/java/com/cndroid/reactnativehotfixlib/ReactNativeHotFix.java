package com.cndroid.reactnativehotfixlib;

import android.content.Context;
import android.os.AsyncTask;
import android.os.Handler;
import android.text.TextUtils;
import android.util.Log;

import com.android.volley.Cache;
import com.android.volley.Network;
import com.android.volley.Request;
import com.android.volley.RequestQueue;
import com.android.volley.Response;
import com.android.volley.VolleyError;
import com.android.volley.toolbox.BasicNetwork;
import com.android.volley.toolbox.DiskBasedCache;
import com.android.volley.toolbox.HurlStack;
import com.android.volley.toolbox.JsonObjectRequest;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.lang.ref.WeakReference;


/**
 * Created by jinbangzhu on 10/11/2016.
 */

public class ReactNativeHotFix {
    public static final String EXTRAROOTBUNDLEPATH = "extraBundleRootPath";
    public static final int CODE_FAIL = 0;
    public static final int CODE_SUCCESS = 1;


    private static final String TAG = "ReactNativeHotFix";

    private RequestQueue mRequestQueue;  // Assume this exists.

    private WeakReference<Context> weakReferenceContext;
    /**
     * url for upgrade
     */
    private String upgradeUrl;

    /**
     * local bundle path where is index.android.bundle
     */
    private String extraBundleRootPath;


    private Handler handler;


    private String patchUrl;


    private long startTime;

    private String extraZipBoundPath;
    private String extraJSPath;
    private String extraInfoPath;


    public static ReactNativeHotFix create(Context context) {
        ReactNativeHotFix fix = new ReactNativeHotFix();
        fix.weakReferenceContext = new WeakReference<>(context);
        fix.initNetwork();
        return fix;
    }


    private void initNetwork() {
        if (weakReferenceContext.get() == null) return;
        // Instantiate the cache
        Cache cache = new DiskBasedCache(weakReferenceContext.get().getCacheDir(), 1024 * 1024); // 1MB cap

        // Set up the network to use HttpURLConnection as the HTTP client.
        Network network = new BasicNetwork(new HurlStack());

        // Instantiate the RequestQueue with the cache and network.
        mRequestQueue = new RequestQueue(cache, network);

        // Start the queue
        mRequestQueue.start();
    }

    public ReactNativeHotFix setUpgradeUrl(String url) {
        this.upgradeUrl = url;
        return this;
    }

    public ReactNativeHotFix setPatchUrl(String patchUrl) {
        this.patchUrl = patchUrl;
        return this;
    }

    public ReactNativeHotFix setExtraBundleRootPath(String path) {
        this.extraBundleRootPath = path;
        return this;
    }

    public ReactNativeHotFix setHandler(Handler handler) {
        this.handler = handler;
        return this;
    }

    public void start() {
        new AsyncTask<Void, Void, Void>() {
            @Override
            protected Void doInBackground(Void... params) {
                initialResource();
                doStart();
                return null;
            }
        }.execute();
    }


    private void initialResource() {
        extraJSPath = extraBundleRootPath + "index.android.jsbundle";
        extraZipBoundPath = extraBundleRootPath + "android.zip";
        extraInfoPath = extraBundleRootPath + "info.json";

        // copy zip file to sdcard
        getBundleZipFile();


        // unzip it if need
        unzipItIfNeed();
    }

    private void unzipItIfNeed() {
        File jsFile = new File(extraJSPath);

        if (!jsFile.exists()) {
            FileUtils.deleteFileOrFolderSilently(jsFile);

            try {
                FileUtils.unzipFile(new File(extraZipBoundPath), extraBundleRootPath);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    /**
     * call this method manual, the MD5 string should from server
     *
     * @param originFileMd5 the old zip file md5
     * @param targetFileMd5 the new zip file md5
     * @param patchFileMd5  the patch file md5
     * @param patchUrl      the patch url on server
     */
    public void start(String originFileMd5, String targetFileMd5, String patchFileMd5, String patchUrl) {
        Log.d(TAG, "originFileMd5:" + originFileMd5);

        File originFile = getBundleZipFile();
        if (originFile.exists()) {
            // get old file md5
            String oldOriginFileMd5 = MD5Helper.calculateMD5(originFile);
            if (!TextUtils.isEmpty(oldOriginFileMd5)) {
                // check md5
                if (oldOriginFileMd5.equals(originFileMd5)) {
                    downloadFile(patchUrl, targetFileMd5, patchFileMd5);
                } else {
                    sendMessageWithFail();
                    Log.d(TAG, "oldOriginFileMd5 not equal originFileMd5");
                }
            } else {
                sendMessageWithFail();
                Log.d(TAG, "oldOriginFileMd5 is null");
            }
        } else {
            sendMessageWithFail();
            Log.d(TAG, "originFile not exists");
        }

    }

    private void doStart() {


        JsonObjectRequest jsonObjectRequest = new JsonObjectRequest(Request.Method.GET, upgradeUrl, null, new Response.Listener<JSONObject>() {
            @Override
            public void onResponse(JSONObject jsonObject) {
                try {
                    String originFileMd5 = jsonObject.getString("originFileMd5");
                    String targetFileMd5 = jsonObject.getString("targetFileMd5");
                    String patchFileMd5 = jsonObject.getString("patchFileMd5");
                    start(originFileMd5, targetFileMd5, patchFileMd5, patchUrl);
                } catch (JSONException e) {
                    e.printStackTrace();
                    sendMessageWithFail();
                }

            }
        }, new Response.ErrorListener() {
            @Override
            public void onErrorResponse(VolleyError error) {
                error.printStackTrace();
                sendMessageWithFail();
            }

        });

        jsonObjectRequest.setTag(getClass().getSimpleName());
        // Add the request to the RequestQueue.
        if (null != mRequestQueue)
            mRequestQueue.add(jsonObjectRequest);

    }

    private File getBundleZipFile() {
        File extraBundleZipFile = new File(extraZipBoundPath);
        if (extraBundleZipFile.exists()) {
            upgradeExtraBundleIFNeed(extraBundleZipFile);
            return extraBundleZipFile;
        } else {
            // copy assets bundleZipFile to sdcard

            createDirsForBundleRoot();
            copyAssetZipToSDcard(extraBundleZipFile);
        }

        return extraBundleZipFile;
    }

    /**
     * upgrade extra bundle
     *
     * @param extraBundleZipFile
     */
    private void upgradeExtraBundleIFNeed(File extraBundleZipFile) {
        if (getDefaultVersionCode() > getExtraVersionCode()) {
            FileUtils.deleteFileOrFolderSilently(extraBundleZipFile);
            removeOldFiles();

            extraBundleZipFile = new File(extraZipBoundPath);
            copyAssetZipToSDcard(extraBundleZipFile);

            try {
                FileUtils.unzipFile(extraBundleZipFile, extraBundleRootPath);
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    /**
     * get int version code
     *
     * @return int
     */
    public int getDefaultVersionCode() {
        String version = getDefaultVersion();
        if (TextUtils.isEmpty(version)) return -1;

        return Integer.parseInt(getDefaultVersion().replace(".", ""));
    }

    /**
     * get version
     *
     * @return
     */
    public String getDefaultVersion() {
        InputStream inputStream;
        try {
            inputStream = weakReferenceContext.get().getAssets().open("info.json");
            String jsonInfo = convertStreamToString(inputStream);

            JSONObject jsonObject = new JSONObject(jsonInfo);

            return jsonObject.getString("version");
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }


    /**
     * extraVersionCode
     * e.g 23
     *
     * @return
     */
    public int getExtraVersionCode() {
        String version = getExtraVersion();
        if (TextUtils.isEmpty(version)) return -1;

        return Integer.parseInt(getDefaultVersion().replace(".", ""));
    }

    /**
     * extraVersion
     * e.g 0.2.3
     *
     * @return
     */
    public String getExtraVersion() {
        try {
            FileInputStream fileInputStream = new FileInputStream(extraInfoPath);
            String jsonInfo = convertStreamToString(fileInputStream);
            JSONObject jsonObject = new JSONObject(jsonInfo);

            return jsonObject.getString("version");
        } catch (Exception e) {
            e.printStackTrace();
        }

        return null;
    }

    private String convertStreamToString(InputStream is) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(is));
        StringBuilder sb = new StringBuilder();
        String line = null;
        while ((line = reader.readLine()) != null) {
            sb.append(line).append("\n");
        }
        reader.close();
        return sb.toString();
    }


    private void copyAssetZipToSDcard(File extraBundleZipFile) {
        if (null != weakReferenceContext.get()) {
            try {
                InputStream inputStream = weakReferenceContext.get().getAssets().open("android.zip");
                OutputStream outputStream = new FileOutputStream(extraBundleZipFile);

                FileUtils.copyFile(inputStream, outputStream);

                inputStream.close();

                outputStream.flush();
                outputStream.close();

            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    private void createDirsForBundleRoot() {
        File extraRoot = new File(extraBundleRootPath);
        if (!extraRoot.exists()) extraRoot.mkdirs();
    }


    private void sendMessageWithFail() {
        if (null != handler) handler.sendEmptyMessage(CODE_FAIL);
    }


    private void downloadFile(String url, final String targetFileMd5, final String patchFileMd5) {
        InputStreamVolleyRequest inputStreamVolleyRequest = new InputStreamVolleyRequest(Request.Method.GET, url, new Response.Listener<byte[]>() {
            @Override
            public void onResponse(byte[] response) {
                try {
                    if (response != null) {
                        savePatchFile(response, patchFileMd5, targetFileMd5);
                    } else {
                        Log.d(TAG, "download file failed");
                        sendMessageWithFail();
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        }, new Response.ErrorListener() {
            @Override
            public void onErrorResponse(VolleyError volleyError) {
                sendMessageWithFail();
                volleyError.printStackTrace();
            }
        }, null);

        inputStreamVolleyRequest.setTag(getClass().getSimpleName());

        if (null != mRequestQueue)
            mRequestQueue.add(inputStreamVolleyRequest);
    }


    private void savePatchFile(byte[] response, String patchFileMd5, String targetFileMd5) throws IOException {
        startTime = System.currentTimeMillis();


        String patchFile = extraBundleRootPath + "_patch";
        FileOutputStream outputStream = new FileOutputStream(patchFile);
        outputStream.write(response);
        outputStream.flush();
        outputStream.close();


        String downloadPatchFileMd5 = MD5Helper.calculateMD5(new File(patchFile));
        if (!TextUtils.isEmpty(downloadPatchFileMd5)) {
            // check file md5
            if (downloadPatchFileMd5.equals(patchFileMd5)) {
                applyPatch(targetFileMd5, patchFile);
            } else {
                sendMessageWithFail();
                Log.d(TAG, "patchFileMd5 not equal downloadPatchFileMd5");
            }
        } else {
            sendMessageWithFail();
            Log.d(TAG, "patchFile is null");

        }
    }

    private void applyPatch(String targetFileMd5, String patchFile) {

        String bundleFilePathTemp = extraZipBoundPath + "_temp";

        BSPatch bsPatch = new BSPatch();
        bsPatch.bspatch(extraZipBoundPath, bundleFilePathTemp, patchFile);

        File zipFileTemp = new File(bundleFilePathTemp);

        String generatedTargetFileMd5 = MD5Helper.calculateMD5(zipFileTemp);

        assert generatedTargetFileMd5 != null;

        if (generatedTargetFileMd5.equals(targetFileMd5)) {

            // delete old zip file
            FileUtils.deleteFileOrFolderSilently(new File(extraZipBoundPath));

            // rename to real bundle
            zipFileTemp.renameTo(new File(extraZipBoundPath));

            // delete patch file
            FileUtils.deleteFileOrFolderSilently(new File(patchFile));
            removeOldFiles();

            try {
                FileUtils.unzipFile(new File(extraZipBoundPath), extraBundleRootPath);

                Log.d(TAG, "success" + extraBundleRootPath + " wastTime=" + (System.currentTimeMillis() - startTime));

                if (null != handler)
                    handler.sendEmptyMessage(CODE_SUCCESS);
            } catch (IOException e) {
                e.printStackTrace();
            }

        } else {
            Log.d(TAG, "generatedTargetFileMd5 not equal targetFileMd5");
            sendMessageWithFail();
        }
    }

    private void removeOldFiles() {
        FileUtils.deleteFileOrFolderSilently(new File(extraJSPath));
        FileUtils.deleteFileOrFolderSilently(new File(extraInfoPath));
        FileUtils.deleteFileOrFolderSilently(new File(extraJSPath + ".meta"));
    }


    public void stop() {
        handler = null;
        weakReferenceContext.clear();
        mRequestQueue.cancelAll(getClass().getSimpleName());
        mRequestQueue.stop();

        mRequestQueue = null;
    }


}
