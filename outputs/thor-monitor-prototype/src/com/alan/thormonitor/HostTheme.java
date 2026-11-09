package com.alan.thormonitor;
import android.content.Context;import android.content.res.Configuration;import android.view.View;import android.widget.LinearLayout;
final class HostTheme {
 static HostPalette current(Context c){return HostPalette.resolve(c.getSharedPreferences("monitor",0).getString("appearance","system"),(c.getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES);}
 static LinearLayout stripe(Context c){LinearLayout row=new LinearLayout(c);for(int color:HostPalette.RAINBOW){View v=new View(c);v.setBackgroundColor(color);row.addView(v,new LinearLayout.LayoutParams(0,Math.round(3*c.getResources().getDisplayMetrics().density),1));}return row;}
}
