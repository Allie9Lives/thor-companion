package com.alan.thormonitor;

import android.animation.*;
import android.graphics.*;
import android.graphics.drawable.Drawable;
import android.view.*;
import android.view.animation.PathInterpolator;
import java.util.ArrayList;

/** Shared, theme-colored focus and press feedback without platform overlays. */
final class HostMotion {
 static final PathInterpolator EASE=new PathInterpolator(.22f,.8f,.22f,1f);
 static final java.util.WeakHashMap<android.widget.ScrollView,ValueAnimator> scrollMotions=new java.util.WeakHashMap<>();
 static void style(View view,int base,int accent,int border,float radius,boolean outline){
  view.setDefaultFocusHighlightEnabled(false);
  view.setFocusable(true);
  view.setOnTouchListener((v,event)->{
   if(event.getActionMasked()==MotionEvent.ACTION_UP)v.post(()->{if(v.isAttachedToWindow())focus(v);});
   return false;
  });
  view.setStateListAnimator(null);
  view.setBackgroundTintList(null);
  if(view.getBackground() instanceof Surface)((Surface)view.getBackground()).release();
  Surface surface=new Surface(view,base,accent,border,radius,outline);if(view.getBackground() instanceof Surface)surface.sharedFocus=((Surface)view.getBackground()).sharedFocus;view.setBackground(surface);
 }
 static void focus(View view){
  View parent=view;while(parent!=null&&!(parent instanceof android.widget.ScrollView))parent=parent.getParent() instanceof View?(View)parent.getParent():null;
  android.widget.ScrollView scroll=parent instanceof android.widget.ScrollView?(android.widget.ScrollView)parent:null;
  if(scroll!=null){ValueAnimator prior=scrollMotions.remove(scroll);if(prior!=null)prior.cancel();}
  int old=scroll==null?0:scroll.getScrollY();view.requestFocusFromTouch();
  if(scroll!=null&&old!=scroll.getScrollY()&&ValueAnimator.areAnimatorsEnabled()){int target=scroll.getScrollY();ValueAnimator prior=scrollMotions.remove(scroll);if(prior!=null)prior.cancel();scroll.scrollTo(0,old);ValueAnimator motion=ValueAnimator.ofInt(old,target);scrollMotions.put(scroll,motion);motion.setDuration(300);motion.setInterpolator(EASE);motion.addUpdateListener(a->{if(!scroll.isAttachedToWindow()){motion.cancel();return;}scroll.scrollTo(0,(int)a.getAnimatedValue());});motion.addListener(new AnimatorListenerAdapter(){public void onAnimationEnd(Animator a){if(scrollMotions.get(scroll)==motion)scrollMotions.remove(scroll);}});motion.start();}
 }
 static void defaults(View view){
  view.setDefaultFocusHighlightEnabled(false);
  if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)defaults(group.getChildAt(i));}
 }
 static void navigation(View root){
  if(root.getTag() instanceof FocusSlide)return;
  FocusSlide slide=new FocusSlide(root);root.setTag(slide);root.getOverlay().add(slide);
  share(root);
  root.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){
   public void onViewAttachedToWindow(View v){slide.attach();}
   public void onViewDetachedFromWindow(View v){slide.detach();}
  });
  if(root.isAttachedToWindow())slide.attach();
 }
 static void share(View view){if(view.getBackground() instanceof Surface)((Surface)view.getBackground()).sharedFocus=true;if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)share(group.getChildAt(i));}}
 static final class FocusSlide extends Drawable implements ViewTreeObserver.OnGlobalFocusChangeListener,ViewTreeObserver.OnPreDrawListener {
  final View root;final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);final RectF current=new RectF(),from=new RectF(),endBounds=new RectF(),nextBounds=new RectF();final int[] rootPosition=new int[2],viewPosition=new int[2];final float density;final int color;View selected;ValueAnimator animator;float fraction=1,radius=14,fromRadius=14,toRadius=14;boolean shown,attached;
  FocusSlide(View root){this.root=root;density=root.getResources().getDisplayMetrics().density;color=HostTheme.current(root.getContext()).accent;}
  void attach(){if(attached)return;attached=true;root.getViewTreeObserver().addOnGlobalFocusChangeListener(this);root.getViewTreeObserver().addOnPreDrawListener(this);onGlobalFocusChanged(null,root.findFocus());}
  void detach(){if(!attached)return;attached=false;if(animator!=null)animator.cancel();if(root.getViewTreeObserver().isAlive()){root.getViewTreeObserver().removeOnGlobalFocusChangeListener(this);root.getViewTreeObserver().removeOnPreDrawListener(this);}}
  boolean contains(View view){for(View v=view;v!=null;){if(v==root)return true;if(!(v.getParent() instanceof View))return false;v=(View)v.getParent();}return false;}
  RectF target(){int[] a=rootPosition,b=viewPosition;root.getLocationOnScreen(a);selected.getLocationOnScreen(b);endBounds.set(b[0]-a[0]+root.getScrollX()+density,b[1]-a[1]+root.getScrollY()+density,b[0]-a[0]+root.getScrollX()+selected.getWidth()-density,b[1]-a[1]+root.getScrollY()+selected.getHeight()-density);return endBounds;}
  public void onGlobalFocusChanged(View old,View next){
   if(next==null||!contains(next)||!(next.getBackground() instanceof Surface)){selected=null;shown=false;invalidateSelf();return;}
   selected=next;Surface surface=(Surface)next.getBackground();toRadius=surface.radius;RectF end=target();
   if(animator!=null)animator.cancel();from.set(current);fromRadius=radius;
   if(!shown||!ValueAnimator.areAnimatorsEnabled()){shown=true;current.set(end);radius=toRadius;fraction=1;invalidateSelf();return;}
   fraction=0;animator=ValueAnimator.ofFloat(0,1);animator.setDuration(280);animator.setInterpolator(EASE);animator.addUpdateListener(a->{fraction=(float)a.getAnimatedValue();position();});animator.start();
  }
  void position(){if(selected==null||!selected.isAttachedToWindow())return;RectF end=target();RectF next=nextBounds;next.set(from.left+(end.left-from.left)*fraction,from.top+(end.top-from.top)*fraction,from.right+(end.right-from.right)*fraction,from.bottom+(end.bottom-from.bottom)*fraction);float rounded=fromRadius+(toRadius-fromRadius)*fraction;if(!current.equals(next)||radius!=rounded){current.set(next);radius=rounded;invalidateSelf();}}
  public boolean onPreDraw(){if(getBounds().width()!=root.getWidth()||getBounds().height()!=root.getHeight())setBounds(0,0,root.getWidth(),root.getHeight());if(shown&&selected!=null)position();return true;}
  public void draw(Canvas c){if(!shown||selected==null)return;c.save();c.clipRect(root.getScrollX(),root.getScrollY(),root.getScrollX()+root.getWidth(),root.getScrollY()+root.getHeight());paint.setColor(color);paint.setStyle(Paint.Style.FILL);paint.setAlpha(24);c.drawRoundRect(current,radius*density,radius*density,paint);paint.setAlpha(255);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(2*density);c.drawRoundRect(current,radius*density,radius*density,paint);c.restore();}
  public void setAlpha(int a){}public void setColorFilter(ColorFilter f){}public int getOpacity(){return PixelFormat.TRANSLUCENT;}
 }
 static final class Surface extends Drawable implements View.OnAttachStateChangeListener {
  final View view;final int base,accent,border;final float radius,density;final boolean outline;
  final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);final RectF bounds=new RectF();float focus,press,targetFocus,targetPress;boolean sharedFocus;ValueAnimator animator;
  Surface(View v,int base,int accent,int border,float radius,boolean outline){view=v;this.base=base;this.accent=accent;this.border=border;this.radius=radius;this.outline=outline;density=v.getResources().getDisplayMetrics().density;v.addOnAttachStateChangeListener(this);}
  void stop(){if(animator!=null){animator.cancel();animator=null;}focus=targetFocus;press=targetPress;}
  void release(){stop();view.removeOnAttachStateChangeListener(this);}
  public void onViewAttachedToWindow(View v){}public void onViewDetachedFromWindow(View v){stop();}
  public boolean isStateful(){return true;}
  protected boolean onStateChange(int[] states){boolean f=false,p=false;for(int state:states){if(state==android.R.attr.state_focused)f=true;if(state==android.R.attr.state_pressed)p=true;}
   final float toFocus=f?1:0,toPress=p?1:0,fromFocus=focus,fromPress=press;
   if(toFocus==targetFocus&&toPress==targetPress)return false;targetFocus=toFocus;targetPress=toPress;
   if(animator!=null)animator.cancel();
   if(!view.isAttachedToWindow()||!ValueAnimator.areAnimatorsEnabled()){focus=toFocus;press=toPress;invalidateSelf();return true;}
   animator=ValueAnimator.ofFloat(0,1);animator.setDuration(p?110:260);animator.setInterpolator(EASE);
   animator.addUpdateListener(a->{float t=(float)a.getAnimatedValue();focus=fromFocus+(toFocus-fromFocus)*t;press=fromPress+(toPress-fromPress)*t;invalidateSelf();});animator.start();return true;
  }
  public void jumpToCurrentState(){if(animator!=null)animator.end();}
  public void draw(Canvas c){float focus=this.sharedFocus?0:this.focus;Rect b=getBounds();float inset=density;RectF r=bounds;r.set(b.left+inset,b.top+inset,b.right-inset,b.bottom-inset);
   paint.setStyle(Paint.Style.FILL);paint.setColor(base);c.drawRoundRect(r,radius*density,radius*density,paint);
   paint.setColor(accent);paint.setAlpha(Math.round(255*(.12f*focus+.12f*press)));c.drawRoundRect(r,radius*density,radius*density,paint);paint.setAlpha(255);
   if(outline||focus>0){paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(density*(1+focus));paint.setColor(blend(outline?border:base,accent,focus));paint.setAlpha(outline?255:Math.round(255*focus));c.drawRoundRect(r,radius*density,radius*density,paint);paint.setAlpha(255);}
  }
  static int blend(int a,int b,float t){return Color.argb(Math.round(Color.alpha(a)+(Color.alpha(b)-Color.alpha(a))*t),Math.round(Color.red(a)+(Color.red(b)-Color.red(a))*t),Math.round(Color.green(a)+(Color.green(b)-Color.green(a))*t),Math.round(Color.blue(a)+(Color.blue(b)-Color.blue(a))*t));}
  public void setAlpha(int alpha){}public void setColorFilter(ColorFilter filter){}public int getOpacity(){return PixelFormat.TRANSLUCENT;}
 }
}
