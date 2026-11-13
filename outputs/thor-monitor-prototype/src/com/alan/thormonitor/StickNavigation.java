package com.alan.thormonitor;

import android.view.View;

/** Intentional stick deflections, with a neutral latch and a slower held repeat. */
final class StickNavigation {
 static final float ENGAGE=.78f,RELEASE=.35f;
 static final long FIRST_REPEAT_MS=460,REPEAT_MS=260;
 private int direction;
 private long nextRepeat,lastMove;
 void reset(){direction=0;nextRepeat=lastMove=0;}
 int next(float x,float y,long now){
  if(!Float.isFinite(x)||!Float.isFinite(y)){reset();return 0;}
  float ax=Math.abs(x),ay=Math.abs(y),magnitude=Math.max(ax,ay);
  if(magnitude<=RELEASE){reset();return 0;}
  int candidate=ay>=ax?(y>0?View.FOCUS_DOWN:View.FOCUS_UP):(x>0?View.FOCUS_RIGHT:View.FOCUS_LEFT);
  if(direction==0){
   if(magnitude<ENGAGE)return 0;
   direction=candidate;lastMove=now;nextRepeat=now+FIRST_REPEAT_MS;return direction;
  }
  if(candidate!=direction){
   if(magnitude<ENGAGE||magnitude<Math.min(ax,ay)*1.35f||now-lastMove<REPEAT_MS)return 0;
   direction=candidate;lastMove=now;nextRepeat=now+FIRST_REPEAT_MS;return direction;
  }
  if(magnitude>=.65f&&now>=nextRepeat){lastMove=now;nextRepeat=now+REPEAT_MS;return direction;}
  return 0;
 }
}
