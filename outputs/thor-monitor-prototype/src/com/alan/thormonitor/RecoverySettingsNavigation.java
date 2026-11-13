package com.alan.thormonitor;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.ActivityOptions;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Display;

/** Keep the local pairing form visible beside Android's debugging settings. */
final class RecoverySettingsNavigation {
 static final String WIRELESS_KEY="toggle_adb_wireless";
 static Intent developerOptions(){
  Bundle args=new Bundle();args.putString(":settings:fragment_args_key",WIRELESS_KEY);
  return new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
   .putExtra(":settings:fragment_args_key",WIRELESS_KEY)
   .putExtra(":settings:show_fragment_args",args);
 }
 static int opposite(int current,int[] presentation,boolean hasDefault){
  if(current!=Display.DEFAULT_DISPLAY&&hasDefault)return Display.DEFAULT_DISPLAY;
  for(int id:presentation)if(id!=current)return id;
  return -1;
 }
 static int otherScreen(Activity activity){
  DisplayManager manager=activity.getSystemService(DisplayManager.class);
  int current=activity.getDisplay()==null?Display.DEFAULT_DISPLAY:activity.getDisplay().getDisplayId();
  Display[] screens=manager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION);
  java.util.ArrayList<Integer> ids=new java.util.ArrayList<>();
  for(Display screen:screens)if((screen.getFlags()&Display.FLAG_PRIVATE)==0)ids.add(screen.getDisplayId());
  int[] candidates=new int[ids.size()];for(int i=0;i<candidates.length;i++)candidates[i]=ids.get(i);
  return opposite(current,candidates,manager.getDisplay(Display.DEFAULT_DISPLAY)!=null);
 }
 static boolean open(Activity activity){
  Intent intent=new Intent("android.settings.WIRELESS_DEBUGGING_SETTINGS");
  if(intent.resolveActivity(activity.getPackageManager())==null)intent=developerOptions();
  if(intent.resolveActivity(activity.getPackageManager())==null)intent=new Intent(Settings.ACTION_SETTINGS);
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
  int target=otherScreen(activity);
  if(target>=0&&activity.getSystemService(ActivityManager.class).isActivityStartAllowedOnDisplay(activity,target,intent)){
   try{ActivityOptions options=ActivityOptions.makeBasic();options.setLaunchDisplayId(target);activity.startActivity(intent,options.toBundle());return true;}
   catch(android.content.ActivityNotFoundException|SecurityException ignored){}
  }
  activity.startActivity(intent);return false;
 }
}
