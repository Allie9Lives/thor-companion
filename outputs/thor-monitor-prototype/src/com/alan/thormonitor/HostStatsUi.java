package com.alan.thormonitor;
import android.content.*;import android.graphics.*;import android.graphics.drawable.GradientDrawable;import android.view.*;import android.widget.*;import java.util.*;import org.json.*;
final class HostStatsUi {
 final Context c;final HostPalette p;
 HostStatsUi(Context c){this.c=c;p=HostTheme.current(c);}
 int dp(float n){return Math.round(n*c.getResources().getDisplayMetrics().density);}
 TextView text(String s,int size,boolean bold){TextView t=new TextView(c);t.setText(s);t.setTextSize(size);t.setTextColor(p.ink);t.setFontFeatureSettings("tnum");t.setLineSpacing(dp(2),1);if(bold)t.setTypeface(Typeface.create("sans-serif-medium",0));return t;}
 TextView muted(String s,int size){TextView t=text(s,size,false);t.setTextColor(p.muted);return t;}
 GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));d.setStroke(dp(1),p.border);return d;}
 void gap(LinearLayout v,int height){Space s=new Space(c);v.addView(s,new LinearLayout.LayoutParams(1,dp(height)));}
 LinearLayout vertical(){LinearLayout v=new LinearLayout(c);v.setOrientation(LinearLayout.VERTICAL);return v;}
 LinearLayout card(LinearLayout parent,String title){LinearLayout v=vertical();v.setPadding(dp(18),dp(18),dp(18),dp(18));v.setBackground(shape(p.card,22));LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(14);parent.addView(v,lp);if(title!=null){v.addView(text(title,18,true));gap(v,14);}return v;}
 Button button(String label,Runnable action){Button b=new Button(c);b.setText(label);b.setAllCaps(false);b.setTextSize(16);b.setTextColor(p.ink);b.setBackground(shape(p.card,14));b.setMinimumHeight(dp(50));b.setPadding(dp(12),dp(10),dp(12),dp(10));b.setOnClickListener(v->action.run());return b;}
 TextView metric(LinearLayout row,String label){LinearLayout cell=vertical();cell.setPadding(0,0,dp(8),0);cell.addView(muted(label,14));gap(cell,4);TextView value=text("—",22,true);cell.addView(value);row.addView(cell,new LinearLayout.LayoutParams(0,-2,1));return value;}
 TextView detail(LinearLayout parent,String label){LinearLayout row=new LinearLayout(c);row.setGravity(Gravity.CENTER_VERTICAL);TextView name=muted(label,16);row.addView(name,new LinearLayout.LayoutParams(0,-2,1));TextView value=text("—",18,true);value.setGravity(Gravity.END);row.addView(value,new LinearLayout.LayoutParams(0,-2,1));parent.addView(row);gap(parent,12);return value;}
 static double number(JSONObject j,String key){return j==null?Double.NaN:j.optDouble(key,Double.NaN);}
 static String value(double n,String format){return Double.isFinite(n)?String.format(Locale.US,format,n):"—";}
 static String capacity(double n){if(!Double.isFinite(n)||n<0)return "—";return n>=1099511627776.0?value(n/1099511627776.0,"%.1f TiB"):value(n/1073741824.0,"%.1f GiB");}
 static BatterySample sample(JSONObject j){double level=number(j,"battery_percent"),plug=number(j,"plugged_code");long at=j.optLong("sampled_at_ms",0);if(!Double.isFinite(level)||!Double.isFinite(plug)||at<=0)return null;double temp=number(j,"battery_temperature_c");return new BatterySample(at,level,plug!=0,j.optBoolean("interactive"),Double.isFinite(temp)?temp:null);}
 static String power(JSONObject j){switch(j.optInt("plugged_code",-1)){case 0:return "On battery";case 1:return "AC power";case 2:return "USB power";case 4:return "Wireless power";default:return "Power source unavailable";}}
 static String charging(JSONObject j){switch(j.optInt("battery_status_code",-1)){case 2:return "Charging";case 3:return "Discharging";case 4:return "Not charging";case 5:return "Full";default:return "Status unavailable";}}
 static final class Bar extends View {
  final HostStatsUi ui;final int color;double fraction=Double.NaN;
  Bar(HostStatsUi u,int color){super(u.c);ui=u;this.color=color;setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);}
  void set(double value){fraction=value;invalidate();}
  protected void onDraw(Canvas c){Paint p=new Paint(3);p.setColor(ui.p.border);c.drawRoundRect(0,0,getWidth(),getHeight(),getHeight()/2f,getHeight()/2f,p);if(Double.isFinite(fraction)){p.setColor(color);c.drawRoundRect(0,0,(float)(getWidth()*Math.max(0,Math.min(1,fraction))),getHeight(),getHeight()/2f,getHeight()/2f,p);}}
 }
 static final class Ring extends View {
  final HostStatsUi ui;double level=Double.NaN;boolean charging;
  Ring(HostStatsUi u){super(u.c);ui=u;setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);}
  void set(double value,boolean charging){level=value;this.charging=charging;invalidate();}
  protected void onDraw(Canvas c){float size=Math.min(getWidth(),getHeight()),left=(getWidth()-size)/2,top=(getHeight()-size)/2;Paint p=new Paint(3);p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(ui.dp(8));p.setStrokeCap(Paint.Cap.ROUND);RectF r=new RectF(left+ui.dp(8),top+ui.dp(8),left+size-ui.dp(8),top+size-ui.dp(8));p.setColor(ui.p.border);c.drawArc(r,140,260,false,p);if(Double.isFinite(level)){p.setColor(level<=20?0xFFDCA755:ui.p.accent);c.drawArc(r,140,(float)(260*Math.max(0,Math.min(1,level/100))),false,p);}p.setColor(ui.p.ink);p.setStrokeWidth(ui.dp(2.5f));float x=getWidth()/2f,y=getHeight()/2f;if(charging){Path bolt=new Path();bolt.moveTo(x+ui.dp(2),y-ui.dp(15));bolt.lineTo(x-ui.dp(7),y+ui.dp(1));bolt.lineTo(x+ui.dp(1),y+ui.dp(1));bolt.lineTo(x-ui.dp(2),y+ui.dp(15));bolt.lineTo(x+ui.dp(8),y-ui.dp(3));bolt.lineTo(x,y-ui.dp(3));bolt.close();p.setStyle(Paint.Style.FILL);c.drawPath(bolt,p);}else{c.drawRoundRect(x-ui.dp(9),y-ui.dp(14),x+ui.dp(9),y+ui.dp(14),ui.dp(3),ui.dp(3),p);c.drawLine(x-ui.dp(4),y-ui.dp(18),x+ui.dp(4),y-ui.dp(18),p);}}
 }
}
