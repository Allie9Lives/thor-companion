package com.alan.thor_companion
import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class ThorFileBridge(private val activity: Activity) {
 private var pending: MethodChannel.Result? = null
 private var source: File? = null
 private val directory get() = File(activity.cacheDir,"thor-transfers").apply { mkdirs() }
 private val credential get() = File(activity.filesDir,"thor-file-connection.bin")
 private fun key(): SecretKey {
  val store=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
  val alias="thor-file-credential"
  if(!store.containsAlias(alias))KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply{init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());generateKey()}
  return store.getKey(alias,null) as SecretKey
 }
 fun call(call: MethodCall,result: MethodChannel.Result) {
  try {when(call.method){
   "cacheDirectory" -> result.success(directory.path)
   "iconCacheDirectory" -> { val icons=File(activity.cacheDir,"thor-app-icons");icons.mkdirs();result.success(icons.path) }
   "forgetConnection" -> {credential.delete();result.success(null)}
   "saveConnection" -> {
    val data=JSONObject(call.arguments as Map<*,*>).toString().toByteArray(Charsets.UTF_8)
    require(data.size<=8192)
    val cipher=Cipher.getInstance("AES/GCM/NoPadding").apply{init(Cipher.ENCRYPT_MODE,key())}
    val temp=File(activity.filesDir,"thor-file-connection.tmp");temp.writeBytes(cipher.iv+cipher.doFinal(data));check(temp.renameTo(credential));result.success(null)
   }
   "loadConnection" -> {
    if(!credential.exists()){result.success(null);return}
    val data=credential.readBytes();require(data.size in 29..16384)
    val cipher=Cipher.getInstance("AES/GCM/NoPadding").apply{init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,data.copyOfRange(0,12)))}
    val json=JSONObject(String(cipher.doFinal(data.copyOfRange(12,data.size)),Charsets.UTF_8))
    val hosts=json.getJSONArray("hosts");result.success(mapOf("hosts" to (0 until hosts.length()).map{hosts.getString(it)},"port" to json.getInt("port"),"pin" to json.getString("pin"),"token" to json.getString("token"),"name" to json.getString("name"),"preferredHost" to json.optString("preferredHost", "")))
   }
   "pickFile","saveFile" -> {
    check(pending==null){"A file picker is already open"}
    if(call.method=="pickFile"){
     pending=result;activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply{type="*/*";addCategory(Intent.CATEGORY_OPENABLE);addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)},8341)
    }else{
     val path=call.argument<String>("path")!!;val name=call.argument<String>("name")!!
     require(name.isNotEmpty()&&!name.contains('/')&&!name.contains('\\')&&name!="."&&name!="..")
     val file=File(path).canonicalFile;require(file.path.startsWith(directory.canonicalPath+File.separator))
     source=file;pending=result;activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply{type="application/octet-stream";addCategory(Intent.CATEGORY_OPENABLE);putExtra(Intent.EXTRA_TITLE,name)},8342)
    }
   }
   else -> result.notImplemented()
  }}catch(e:Exception){pending=null;result.error("files","Could not open Files or the saved connection.",null)}
 }
 fun activityResult(request:Int,result:Int,data:Intent?):Boolean {
  if(request!=8341&&request!=8342)return false
  val callback=pending ?: return true
  pending=null
  if(result!=Activity.RESULT_OK||data?.data==null){callback.success(null);return true}
  val uri=data.data!!
  Thread {
   var copy:File?=null
   try{
    val response:Any
    if(request==8341){
     var name="file";activity.contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use{if(it.moveToFirst())name=it.getString(0)}
     copy=File(directory,"upload-"+java.util.UUID.randomUUID());activity.contentResolver.openInputStream(uri)!!.use{input->copy!!.outputStream().use{input.copyTo(it,65536)}}
     response=mapOf("path" to copy!!.path,"name" to name,"size" to copy!!.length())
    }else{
     val file=source ?: error("Missing download");activity.contentResolver.openOutputStream(uri,"w")!!.use{output->file.inputStream().use{it.copyTo(output,65536)}};response=true
    }
    activity.runOnUiThread{callback.success(response)}
   }catch(e:Exception){copy?.delete();activity.runOnUiThread{callback.error("files","Could not copy the selected file. Check available space and file access.",null)}}
  }.start();return true
 }
}
