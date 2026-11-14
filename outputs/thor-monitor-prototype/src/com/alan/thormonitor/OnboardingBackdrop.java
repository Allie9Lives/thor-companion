package com.alan.thormonitor;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.View;

/** A tiled, low-contrast lightning pattern. One tile of travel is an exact loop. */
final class OnboardingBackdrop extends View {
 private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
 private final Path bolt=new Path();
 private final float density;
 private boolean running=true;
 private long lastFrame;
 private double phase;
 OnboardingBackdrop(Context context,int color){
  super(context);phase=(android.os.SystemClock.elapsedRealtime()%18000)/18000.0;density=getResources().getDisplayMetrics().density;
  paint.setColor(color);paint.setAlpha(19);
  bolt.moveTo(3,-18);bolt.lineTo(-11,3);bolt.lineTo(-2,3);
  bolt.lineTo(-5,18);bolt.lineTo(12,-5);bolt.lineTo(3,-5);bolt.close();
  setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);setFocusable(false);setClickable(false);
 }
 void setRunning(boolean value){running=value;lastFrame=0;if(value)invalidate();}
 static double advance(double phase,double seconds){return (phase+Math.max(0,Math.min(seconds,.1))/18.0)%1.0;}
 @Override protected void onDraw(Canvas canvas){
  super.onDraw(canvas);
  boolean motion=running&&isShown()&&android.animation.ValueAnimator.areAnimatorsEnabled();
  long now=android.os.SystemClock.elapsedRealtimeNanos();
  if(motion&&lastFrame!=0)phase=advance(phase,(now-lastFrame)/1e9);
  lastFrame=motion?now:0;
  float tile=104*density,offset=(float)phase*tile;
  int save=canvas.save();canvas.translate(getWidth()/2f,getHeight()/2f);canvas.rotate(-18);
  float reach=(float)Math.hypot(getWidth(),getHeight())/2+tile*2;
  for(float y=-((int)(reach/tile)+1)*tile;y<=reach;y+=tile){
   for(float x=-((int)(reach/tile)+1)*tile;x<=reach;x+=tile){
    int item=canvas.save();canvas.translate(x+offset,y);canvas.scale(density,density);canvas.drawPath(bolt,paint);canvas.restoreToCount(item);
   }
  }
  canvas.restoreToCount(save);if(motion)postInvalidateOnAnimation();
 }
 @Override protected void onWindowVisibilityChanged(int visibility){super.onWindowVisibilityChanged(visibility);lastFrame=0;if(visibility==VISIBLE)invalidate();}
 @Override protected void onDetachedFromWindow(){lastFrame=0;super.onDetachedFromWindow();}
}
