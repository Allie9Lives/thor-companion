package com.alan.thormonitor;

import android.content.Context;
import android.os.Build;
import android.provider.Settings;

/** AYN's launcher otherwise force-stops packages when removing their task. */
final class HostBackgroundProtection {
    static final String KEY="app_whiteList";
    static boolean supported(){return "AYN".equalsIgnoreCase(Build.MANUFACTURER)&&Build.MODEL.toLowerCase(java.util.Locale.ROOT).contains("thor");}
    static boolean contains(String list,String pkg){if(list!=null)for(String item:list.split(",",-1))if(item.equals(pkg))return true;return false;}
    static String update(String list,String pkg,boolean enabled){
        if(enabled)return contains(list,pkg)?list:list==null||list.isEmpty()?pkg:list+","+pkg;
        if(!contains(list,pkg))return list;
        java.util.ArrayList<String> keep=new java.util.ArrayList<>();for(String item:list.split(",",-1))if(!item.equals(pkg))keep.add(item);
        return String.join(",",keep);
    }
    static boolean active(Context c){try{return supported()&&contains(Settings.System.getString(c.getContentResolver(),KEY),c.getPackageName());}catch(Exception e){return false;}}
    static boolean apply(Context c){
        if(!supported())return false;
        try{
            String before=Settings.System.getString(c.getContentResolver(),KEY);
            String after=update(before,c.getPackageName(),c.getSharedPreferences("monitor",0).getBoolean("protect_recents",true));
            if(!java.util.Objects.equals(before,after)&&(before==null||!Settings.System.putString(c.getContentResolver(),KEY,after)))return false;
            return active(c);
        }catch(RuntimeException e){return false;}
    }
    static boolean needsUpdate(Context c){return supported()&&active(c)!=c.getSharedPreferences("monitor",0).getBoolean("protect_recents",true);}
    static String status(Context c){return active(c)?"Protected from Recents cleanup":"Finish Recovery setup to protect monitoring.";}
}
