package com.alan.thormonitor;
import android.app.Activity;import android.view.*;import android.widget.*;
final class HostUpdatesView extends LinearLayout {
 final Activity activity;final HostStatsUi ui;final TextView status,latest;final Button check,download,install,cancel;
 HostUpdatesView(Activity a){super(a);activity=a;ui=new HostStatsUi(a);setOrientation(VERTICAL);addView(ui.text("Updates",28,true));ui.gap(this,16);
  LinearLayout host=ui.card(this,null);host.setFocusable(false);host.setDescendantFocusability(FOCUS_AFTER_DESCENDANTS);host.addView(ui.iconLabel("Thor Monitor","update",18,true));ui.gap(host,12);host.addView(ui.muted("Installed · "+HostUpdates.installed(a),16));latest=ui.muted("GitHub releases",16);host.addView(latest);ui.gap(host,12);status=ui.text(HostUpdates.status,18,true);host.addView(status);
  check=ui.button("Check for updates",()->HostUpdates.check(a,true));host.addView(check);ui.gap(host,8);
  download=ui.button("Download update",()->HostUpdates.download(a));host.addView(download);
  cancel=ui.button("Cancel download",()->HostUpdates.cancel(a));host.addView(cancel);
  install=ui.button("Install update",()->HostUpdates.install(a));host.addView(install);
  ui.gap(host,8);host.addView(ui.muted("Downloads are checked before Android asks you to install.",14));
  LinearLayout automatic=new LinearLayout(a);automatic.setGravity(Gravity.CENTER_VERTICAL);TextView label=ui.text("Check when app opens",16,false);automatic.addView(label,new LayoutParams(0,-2,1));Switch enabled=new Switch(a);enabled.setContentDescription("Check when app opens");enabled.setChecked(a.getSharedPreferences("monitor",0).getBoolean("updates_on_open",false));enabled.setThumbTintList(android.content.res.ColorStateList.valueOf(ui.p.ink));enabled.setTrackTintList(new android.content.res.ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[]{}},new int[]{ui.p.accent,ui.p.border}));enabled.setFocusable(false);automatic.addView(enabled);automatic.setMinimumHeight(ui.dp(56));HostMotion.style(automatic,android.graphics.Color.TRANSPARENT,ui.p.accent,ui.p.border,14,false);automatic.setContentDescription("Check when app opens");automatic.setOnClickListener(v->enabled.setChecked(!enabled.isChecked()));enabled.setOnCheckedChangeListener((v,on)->{a.getSharedPreferences("monitor",0).edit().putBoolean("updates_on_open",on).apply();if(on)HostUpdates.check(a,false);});host.addView(automatic);
  LinearLayout obtainium=ui.card(this,null);obtainium.setFocusable(false);obtainium.setDescendantFocusability(FOCUS_AFTER_DESCENDANTS);obtainium.addView(ui.text("Obtainium",18,true));ui.gap(obtainium,12);obtainium.addView(ui.muted("Optional update manager for Android apps.",16));ui.gap(obtainium,10);obtainium.addView(ui.button("Add Thor Monitor to Obtainium",()->HostUpdates.obtainium(a)));
  addView(ui.button("View GitHub releases",()->HostUpdates.open(a,HostRelease.REPO+"/releases/latest")));refresh();
 }
 View nextControl(View root,View focused,int direction){
  java.util.ArrayList<View> controls=new java.util.ArrayList<>();root.addFocusables(controls,View.FOCUS_FORWARD,View.FOCUSABLES_ALL);
  controls.removeIf(v->!v.isEnabled()||v.getVisibility()!=VISIBLE||!v.isClickable());
  int index=controls.indexOf(focused);int next=index<0?(direction==View.FOCUS_UP?controls.size()-1:0):index+(direction==View.FOCUS_UP?-1:1);
  return next>=0&&next<controls.size()?controls.get(next):null;
 }
 void refresh(){HostUpdates.poll(activity);status.setText(HostUpdates.ready(activity)?"Update ready to install.":HostUpdates.status);latest.setText(HostUpdates.latest==null?"GitHub releases":"Latest · "+HostUpdates.latest.version);check.setEnabled(!HostUpdates.busy);download.setVisibility(!HostUpdates.ready(activity)&&HostUpdates.latest!=null&&HostRelease.compare(HostUpdates.latest.version,HostUpdates.installed(activity))>0?VISIBLE:GONE);download.setEnabled(!HostUpdates.busy&&!HostUpdates.downloading(activity));install.setVisibility(HostUpdates.ready(activity)?VISIBLE:GONE);install.setEnabled(!HostUpdates.busy);cancel.setVisibility(HostUpdates.downloading(activity)?VISIBLE:GONE);cancel.setEnabled(!HostUpdates.busy);}
}
