package com.alan.thormonitor;
import android.content.*;import android.graphics.Typeface;import android.graphics.drawable.GradientDrawable;import android.hardware.display.DisplayManager;import android.provider.Settings;import android.view.*;import android.view.animation.DecelerateInterpolator;import android.animation.ValueAnimator;import android.animation.Animator;import android.animation.AnimatorListenerAdapter;import android.view.animation.AccelerateInterpolator;import android.widget.*;import java.util.*;import java.util.function.Consumer;
/** A short-lived, non-focus-stealing locator panel on each internal display. */
final class LocatorStopPanel {
 static final int ENTER_MS=220,EXIT_MS=220,BLUR_DP=16;
 private static final android.os.Handler main=new android.os.Handler(android.os.Looper.getMainLooper());
 private static final List<Overlay> overlays=new ArrayList<>();
 private static final class Overlay {
  final WindowManager manager;final View panel;final WindowManager.LayoutParams params;
  Consumer<Boolean> listener;ValueAnimator backdrop;Runnable cleanup;boolean removed,blurEnabled,exiting;float reveal;
  Overlay(WindowManager m,View p,WindowManager.LayoutParams lp){manager=m;panel=p;params=lp;}
 }
 static boolean allowed(Context c){return Settings.canDrawOverlays(c);}
 static boolean visible(){return !overlays.isEmpty();}
 static int dp(Context c,int value){return Math.round(value*c.getResources().getDisplayMetrics().density);}
 static void configure(Overlay entry){
  entry.params.setBlurBehindRadius(entry.blurEnabled?Math.round(dp(entry.panel.getContext(),BLUR_DP)*entry.reveal):0);
  entry.params.dimAmount=(entry.blurEnabled?.12f:.34f)*entry.reveal;
 }
 static void update(Overlay entry){if(entry.removed)return;configure(entry);try{entry.manager.updateViewLayout(entry.panel,entry.params);}catch(IllegalArgumentException ignored){}}
 static void show(Context app){
  hide();if(!allowed(app)||!app.getSharedPreferences("monitor",0).getBoolean("finder_overlay",true))return;
  for(Display display:app.getSystemService(DisplayManager.class).getDisplays())try{
   if(display.getDisplayId()!=0){try{if(((Integer)Display.class.getDeclaredMethod("getType").invoke(display))!=1)continue;}catch(Exception e){continue;}}
   Context c=app.createWindowContext(display,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,null);WindowManager wm=c.getSystemService(WindowManager.class);
   LinearLayout panel=createPanel(c,HostTheme.current(c));int width=Math.min(dp(c,352),c.getResources().getDisplayMetrics().widthPixels-dp(c,40));
   int flags=WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL|WindowManager.LayoutParams.FLAG_DIM_BEHIND|WindowManager.LayoutParams.FLAG_BLUR_BEHIND;
   WindowManager.LayoutParams params=new WindowManager.LayoutParams(width,WindowManager.LayoutParams.WRAP_CONTENT,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,flags,android.graphics.PixelFormat.TRANSLUCENT);params.gravity=Gravity.CENTER;params.setTitle("Thor locator Stop");
   Overlay entry=new Overlay(wm,panel,params);boolean animate=ValueAnimator.areAnimatorsEnabled();entry.reveal=animate?0:1;entry.blurEnabled=wm.isCrossWindowBlurEnabled();configure(entry);
   if(animate){panel.setAlpha(0);panel.setScaleX(.94f);panel.setScaleY(.94f);panel.setTranslationY(dp(c,8));}
   wm.addView(panel,params);overlays.add(entry);
   entry.listener=enabled->{if(!entry.removed){entry.blurEnabled=enabled;update(entry);}};
   try{wm.addCrossWindowBlurEnabledListener(entry.listener);}catch(Exception ignored){entry.listener=null;}
   if(animate){
    panel.animate().alpha(1).scaleX(1).scaleY(1).translationY(0).setDuration(ENTER_MS).setInterpolator(new DecelerateInterpolator(1.5f)).start();
    entry.backdrop=ValueAnimator.ofFloat(0,1);entry.backdrop.setDuration(ENTER_MS);entry.backdrop.setInterpolator(new DecelerateInterpolator(1.5f));entry.backdrop.addUpdateListener(v->{entry.reveal=(Float)v.getAnimatedValue();update(entry);});entry.backdrop.start();
   }
  }catch(Exception ignored){}
 }
 static void refresh(Context c){for(Overlay entry:overlays)if(!entry.removed&&!entry.exiting){show(c.getApplicationContext());return;}}
 static LinearLayout createPanel(Context c,HostPalette theme){
  LinearLayout panel=new LinearLayout(c);panel.setOrientation(LinearLayout.VERTICAL);panel.setPadding(dp(c,22),dp(c,20),dp(c,22),dp(c,20));
   GradientDrawable background=new GradientDrawable();background.setColor(theme.card);background.setCornerRadius(dp(c,22));background.setStroke(dp(c,1),theme.border);panel.setBackground(background);panel.setElevation(dp(c,18));
   if(theme.rainbow){panel.addView(HostTheme.stripe(c));Space gap=new Space(c);panel.addView(gap,new LinearLayout.LayoutParams(1,dp(c,16)));}
   TextView title=new TextView(c);title.setText("Find my Thor");title.setTextColor(theme.ink);title.setTextSize(22);title.setTypeface(Typeface.create("sans-serif-medium",0));panel.addView(title);
   TextView body=new TextView(c);body.setText("Tap below to stop the locator sound.");body.setTextColor(theme.muted);body.setTextSize(16);body.setPadding(0,dp(c,8),0,dp(c,16));panel.addView(body);
   Button stop=new Button(c);stop.setText("Stop sound");stop.setAllCaps(false);stop.setTextSize(18);stop.setTextColor(theme.onAccent);stop.setMinHeight(dp(c,54));stop.setContentDescription("Stop Find my Thor sound");GradientDrawable button=new GradientDrawable();button.setColor(theme.accent);button.setCornerRadius(dp(c,12));stop.setBackground(button);stop.setOnClickListener(v->FindThor.requestStop());panel.addView(stop,new LinearLayout.LayoutParams(-1,dp(c,56)));
   return panel;
 }

 static void dismiss(){
  for(Overlay entry:new ArrayList<>(overlays)){
   if(entry.removed||entry.exiting)continue;entry.exiting=true;
   entry.panel.animate().cancel();if(entry.backdrop!=null)entry.backdrop.cancel();
   if(!ValueAnimator.areAnimatorsEnabled()){remove(entry);continue;}
   final float alpha=entry.panel.getAlpha(),sx=entry.panel.getScaleX(),sy=entry.panel.getScaleY(),y=entry.panel.getTranslationY(),reveal=entry.reveal;
   entry.backdrop=ValueAnimator.ofFloat(0,1);entry.backdrop.setDuration(EXIT_MS);entry.backdrop.setInterpolator(new AccelerateInterpolator(1.25f));
   entry.backdrop.addUpdateListener(animation->{if(entry.removed)return;float t=(Float)animation.getAnimatedValue();entry.panel.setAlpha(alpha*(1-t));entry.panel.setScaleX(sx+(.94f-sx)*t);entry.panel.setScaleY(sy+(.94f-sy)*t);entry.panel.setTranslationY(y+(dp(entry.panel.getContext(),8)-y)*t);entry.reveal=reveal*(1-t);update(entry);});
   entry.backdrop.addListener(new AnimatorListenerAdapter(){@Override public void onAnimationEnd(Animator animation){if(!entry.removed)remove(entry);}});entry.backdrop.start();
   // Choreographer may pause when the lid closes; do not retain an invisible window.
   float scale=android.provider.Settings.Global.getFloat(entry.panel.getContext().getContentResolver(),"animator_duration_scale",1);
   entry.cleanup=()->remove(entry);main.postDelayed(entry.cleanup,(long)(EXIT_MS*Math.max(1,scale))+1000);
  }
 }
 private static void remove(Overlay entry){
  if(entry.removed)return;entry.removed=true;if(entry.cleanup!=null)main.removeCallbacks(entry.cleanup);entry.panel.animate().cancel();if(entry.backdrop!=null)entry.backdrop.cancel();if(entry.listener!=null)try{entry.manager.removeCrossWindowBlurEnabledListener(entry.listener);}catch(Exception ignored){}try{entry.manager.removeViewImmediate(entry.panel);}catch(Exception ignored){}overlays.remove(entry);
 }
 static void hide(){for(Overlay entry:new ArrayList<>(overlays))remove(entry);}
}
