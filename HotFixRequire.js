/**
 * Created by jinbangzhu on 17/11/2016.
 */

GLOBAL = require('./HotFixGlobals');

var EXTRA_PATH;

var imgRequire = function (url) {
    console.log("image:" + url);

    if (GLOBAL.EXTRA_ASSETS_PATCH) {
        var len = url.length;
        var imageName = url.substring(2, len);
        var finalPath = 'file://' + GLOBAL.EXTRA_ASSETS_PATCH + imageName;
        // console.log("ok use this " + finalPath);
        // "file:///storage/emulated/0/remoteReact/img_zoo_dribbble.jpg"
        return {uri: finalPath, isStatic: true};
    } else {
        // console.log("extraPath is null");
        return {uri: "nil"};
    }
};

function checkURL(url) {
    return (url.match(/\.(jpeg|jpg|gif|png)$/) != null);
}


module.exports = imgRequire;