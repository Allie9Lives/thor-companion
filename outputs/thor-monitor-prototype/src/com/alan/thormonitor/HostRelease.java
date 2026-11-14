package com.alan.thormonitor;
import org.json.*;import java.util.regex.*;
/** Only stable host APKs from this repository are update candidates. */
final class HostRelease {
 static final String REPO="https://github.com/Allie9Lives/thor-companion";
 static final String FILTER="^Thor-Monitor-([0-9]+\\.[0-9]+\\.[0-9]+)\\.apk$";
 final String version,name,url,digest;final long size;
 HostRelease(String v,String n,String u,String d,long s){version=v;name=n;url=u;digest=d;size=s;}
 static HostRelease parse(JSONObject release)throws Exception{
  if(release.optBoolean("draft")||release.optBoolean("prerelease"))throw new Exception("No stable host update available.");
  JSONArray assets=release.optJSONArray("assets");HostRelease best=null;
  for(int i=0;assets!=null&&i<assets.length();i++){
   JSONObject a=assets.getJSONObject(i);String name=a.optString("name"),url=a.optString("browser_download_url");Matcher m=Pattern.compile(FILTER).matcher(name);
   if(!m.matches()||!url.startsWith(REPO+"/releases/download/")||url.contains("?")||url.contains("#"))continue;
   try{compare(m.group(1),"0.0.0");}catch(NumberFormatException invalid){continue;}
   String digest=a.optString("digest");long size=a.optLong("size");if(!digest.matches("sha256:[a-fA-F0-9]{64}")||size<=0||size>100*1024*1024)continue;
   HostRelease item=new HostRelease(m.group(1),name,url,digest.substring(7).toLowerCase(java.util.Locale.ROOT),size);
   if(best==null||compare(item.version,best.version)>0)best=item;
  }
  if(best==null)throw new Exception("No verified Thor Monitor APK in the latest release.");return best;
 }
 static int compare(String a,String b){String[] x=a.replaceFirst("^v","").split("[.+-]"),y=b.replaceFirst("^v","").split("[.+-]");for(int i=0;i<3;i++){int n=i<x.length?Integer.parseInt(x[i]):0,m=i<y.length?Integer.parseInt(y[i]):0;if(n!=m)return Integer.compare(n,m);}return 0;}
 static JSONObject obtainiumConfig()throws JSONException{return new JSONObject().put("id","com.alan.thormonitor").put("url",REPO).put("author","Allie9Lives").put("name","Thor Monitor").put("additionalSettings",new JSONObject().put("apkFilterRegEx",FILTER).put("includePrereleases",false).put("versionDetection",true).toString());}
}
