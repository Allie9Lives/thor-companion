package com.alan.thormonitor;
import android.content.*;import android.content.pm.PackageManager;import java.util.*;
final class ThorAppearance {
 static void applyColor(Context c,String value){
  int selected=ThorColor.index(value);if(selected<0)throw new IllegalArgumentException("Unknown Thor color");
  PackageManager manager=c.getPackageManager();List<PackageManager.ComponentEnabledSetting> changes=new ArrayList<>();
  for(int i=0;i<ThorColor.ALIASES.length;i++)changes.add(new PackageManager.ComponentEnabledSetting(new ComponentName(c,c.getPackageName()+"."+ThorColor.ALIASES[i]),i==selected?PackageManager.COMPONENT_ENABLED_STATE_ENABLED:PackageManager.COMPONENT_ENABLED_STATE_DISABLED,PackageManager.DONT_KILL_APP));
  // Switch all launcher aliases atomically without stopping the monitoring service.
  manager.setComponentEnabledSettings(changes);
  c.getSharedPreferences("monitor",0).edit().putString("thor_color",value).putString("appearance",ThorColor.theme(value)).apply();
 }
}
