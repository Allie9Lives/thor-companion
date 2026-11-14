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
 static boolean touchInput=true;
 static boolean transferringFocus;
 static final java.util.WeakHashMap<android.widget.ScrollView,ValueAnimator> scrollMotions=new java.util.WeakHashMap<>();
 static void style(View view,int base,int accent,int border,float radius,boolean outline){
  view.setDefaultFocusHighlightEnabled(false);
  view.setFocusable(true);
  final float[] down=new float[2];final boolean[] tapping={false};final int slop=ViewConfiguration.get(view.getContext()).getScaledTouchSlop();
  view.setOnTouchListener((v,event)->{
   int action=event.getActionMasked();
   if(action==MotionEvent.ACTION_DOWN){touch(v);down[0]=event.getX();down[1]=event.getY();tapping[0]=true;}
   else if(action==MotionEvent.ACTION_MOVE&&(Math.abs(event.getX()-down[0])>slop||Math.abs(event.getY()-down[1])>slop))tapping[0]=false;
   else if(action==MotionEvent.ACTION_CANCEL)tapping[0]=false;
   else if(action==MotionEvent.ACTION_UP){if(tapping[0]&&event.getX()>=0&&event.getY()>=0&&event.getX()<v.getWidth()&&event.getY()<v.getHeight())remember(v);tapping[0]=false;}
   return false;
  });
  view.setStateListAnimator(null);
  view.setBackgroundTintList(null);
  if(view.getBackground() instanceof Surface)((Surface)view.getBackground()).release();
  Surface surface=new Surface(view,base,accent,border,radius,outline);if(view.getBackground() instanceof Surface)surface.sharedFocus=((Surface)view.getBackground()).sharedFocus;view.setBackground(surface);
 }
 static FocusSlide slide(View view){for(View current=view;current!=null;current=current.getParent() instanceof View?(View)current.getParent():null)if(current.getTag() instanceof FocusSlide)return (FocusSlide)current.getTag();return null;}
 static void remember(View view){FocusSlide slide=slide(view);if(slide!=null&&slide.valid(view))slide.anchor=view;}
 static View anchor(View root,View fallback){FocusSlide slide=slide(root);if(slide!=null&&slide.valid(slide.anchor))return slide.anchor;return fallback;}
 // Exit Android touch mode at the remembered item before directional search.
 // Android may briefly focus a default control while changing input modes;
 // keep that internal handoff from moving the viewport or focus outline.
 static View controllerAnchor(View root,View fallback){
  View view=anchor(root,fallback);touchInput=false;
  if(view==null)return null;
  if(view.isInTouchMode()||root!=null&&root.findFocus()!=view){
   ScrollPosition viewport=new ScrollPosition(view);
   transferringFocus=true;
   try{view.requestFocusFromTouch();}finally{transferringFocus=false;viewport.restore();}
   remember(view);
  }
  FocusSlide slide=slide(view);if(slide!=null&&!slide.shown)slide.onGlobalFocusChanged(null,view);
  return view;
 }
 static final class ScrollPosition {
  final ArrayList<android.widget.ScrollView> parents=new ArrayList<>();final ArrayList<Integer> positions=new ArrayList<>();
  ScrollPosition(View view){for(View p=view;p!=null;p=p.getParent() instanceof View?(View)p.getParent():null)if(p instanceof android.widget.ScrollView){parents.add((android.widget.ScrollView)p);positions.add(p.getScrollY());}}
  void restore(){for(int n=0;n<parents.size();n++)if(parents.get(n).isAttachedToWindow())parents.get(n).scrollTo(0,positions.get(n));}
 }
 static void restoreFocus(View view){remember(view);FocusSlide slide=slide(view);if(slide!=null)slide.hide();view.requestFocusFromTouch();}
 static void controllerInput(){touchInput=false;}
 static void touch(View view){
  touchInput=true;FocusSlide slide=slide(view);if(slide!=null)slide.hide();
  for(ValueAnimator motion:new ArrayList<>(scrollMotions.values()))motion.cancel();scrollMotions.clear();
 }
 static void focus(View view){
  touchInput=false;remember(view);
  View parent=view;while(parent!=null&&!(parent instanceof android.widget.ScrollView))parent=parent.getParent() instanceof View?(View)parent.getParent():null;
  android.widget.ScrollView scroll=parent instanceof android.widget.ScrollView?(android.widget.ScrollView)parent:null;
  if(scroll!=null){ValueAnimator prior=scrollMotions.remove(scroll);if(prior!=null)prior.cancel();}
  int old=scroll==null?0:scroll.getScrollY();view.requestFocusFromTouch();
  FocusSlide slide=slide(view);if(slide!=null&&(!slide.shown||slide.selected!=view))slide.onGlobalFocusChanged(null,view);
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
 static final class FocusSlide extends Drawable implements ViewTreeObserver.OnGlobalFocusChangeListener,ViewTreeObserver.OnPreDrawListener,ViewTreeObserver.OnTouchModeChangeListener {
  final View root;final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);final RectF current=new RectF(),from=new RectF(),endBounds=new RectF(),nextBounds=new RectF();final int[] rootPosition=new int[2],viewPosition=new int[2];final float density;final int color;View selected,anchor;ValueAnimator animator;float fraction=1,radius=14,fromRadius=14,toRadius=14;boolean shown,attached;
  FocusSlide(View root){this.root=root;density=root.getResources().getDisplayMetrics().density;color=HostTheme.current(root.getContext()).accent;}
  void attach(){if(attached)return;attached=true;root.getViewTreeObserver().addOnGlobalFocusChangeListener(this);root.getViewTreeObserver().addOnPreDrawListener(this);root.getViewTreeObserver().addOnTouchModeChangeListener(this);onGlobalFocusChanged(null,root.findFocus());}
  void detach(){if(!attached)return;attached=false;if(animator!=null)animator.cancel();if(root.getViewTreeObserver().isAlive()){root.getViewTreeObserver().removeOnGlobalFocusChangeListener(this);root.getViewTreeObserver().removeOnPreDrawListener(this);root.getViewTreeObserver().removeOnTouchModeChangeListener(this);}}
  public void onTouchModeChanged(boolean inTouchMode){
   if(inTouchMode||transferringFocus||!touchInput||!root.hasWindowFocus()||!valid(anchor))return;
   View remembered=anchor;ScrollPosition viewport=new ScrollPosition(remembered);
   root.post(()->{if(!root.isAttachedToWindow()||!root.hasWindowFocus()||root.isInTouchMode()||!touchInput||!valid(remembered))return;anchor=remembered;viewport.restore();controllerAnchor(root,root.findFocus());});
  }
  boolean contains(View view){for(View v=view;v!=null;){if(v==root)return true;if(!(v.getParent() instanceof View))return false;v=(View)v.getParent();}return false;}
  boolean valid(View view){return view!=null&&contains(view)&&view.isAttachedToWindow()&&view.isShown()&&view.isEnabled()&&view.isFocusable();}
  RectF target(){int[] a=rootPosition,b=viewPosition;root.getLocationOnScreen(a);selected.getLocationOnScreen(b);endBounds.set(b[0]-a[0]+root.getScrollX()+density,b[1]-a[1]+root.getScrollY()+density,b[0]-a[0]+root.getScrollX()+selected.getWidth()-density,b[1]-a[1]+root.getScrollY()+selected.getHeight()-density);return endBounds;}
  void hide(){if(animator!=null){animator.cancel();animator=null;}shown=false;selected=null;fraction=1;invalidateSelf();}
  public void onGlobalFocusChanged(View old,View next){
   if(transferringFocus)return;
   if(touchInput){if(next instanceof android.widget.EditText&&valid(next))anchor=next;hide();return;}
   if(next==selected&&shown){position();return;}
   if(next==null||!contains(next)||!(next.getBackground() instanceof Surface)){selected=null;shown=false;invalidateSelf();return;}
   anchor=next;selected=next;Surface surface=(Surface)next.getBackground();toRadius=surface.radius;RectF end=target();
   if(animator!=null)animator.cancel();from.set(current);fromRadius=radius;
   if(!shown||!ValueAnimator.areAnimatorsEnabled()){shown=true;current.set(end);radius=toRadius;fraction=1;invalidateSelf();return;}
   fraction=0;animator=ValueAnimator.ofFloat(0,1);animator.setDuration(280);animator.setInterpolator(EASE);animator.addUpdateListener(a->{fraction=(float)a.getAnimatedValue();position();});animator.start();
  }
  void position(){if(selected==null||!selected.isAttachedToWindow())return;RectF end=target();RectF next=nextBounds;next.set(from.left+(end.left-from.left)*fraction,from.top+(end.top-from.top)*fraction,from.right+(end.right-from.right)*fraction,from.bottom+(end.bottom-from.bottom)*fraction);float rounded=fromRadius+(toRadius-fromRadius)*fraction;if(!current.equals(next)||radius!=rounded){current.set(next);radius=rounded;invalidateSelf();}}
  public boolean onPreDraw(){if(touchInput){if(shown)hide();return true;}if(!shown){View focus=valid(anchor)?anchor:root.findFocus();if(focus!=null&&focus.getBackground() instanceof Surface)onGlobalFocusChanged(null,focus);}if(getBounds().width()!=root.getWidth()||getBounds().height()!=root.getHeight())setBounds(0,0,root.getWidth(),root.getHeight());if(shown&&selected!=null)position();return true;}
  public void draw(Canvas c){if(touchInput||!shown||selected==null)return;c.save();c.clipRect(root.getScrollX(),root.getScrollY(),root.getScrollX()+root.getWidth(),root.getScrollY()+root.getHeight());Surface surface=(Surface)selected.getBackground();int focusColor=surface.base==color?surface.accent:color;paint.setColor(focusColor);paint.setStyle(Paint.Style.FILL);paint.setAlpha(24);c.drawRoundRect(current,radius*density,radius*density,paint);paint.setAlpha(255);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(2*density);c.drawRoundRect(current,radius*density,radius*density,paint);c.restore();}
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
