package com.alan.thormonitor;
import android.content.Context;import android.content.res.Configuration;import android.view.View;import android.widget.LinearLayout;
final class HostTheme {
 static String name(Context c){String choice=c.getSharedPreferences("monitor",0).getString("appearance","system");if("clearPurple".equals(choice)||"rainbow".equals(choice)||"dark".equals(choice)||"light".equals(choice))return choice;return current(c).dark?"dark":"light";}
 static HostPalette current(Context c){return HostPalette.resolve(c.getSharedPreferences("monitor",0).getString("appearance","system"),(c.getResources().getConfiguration().uiMode&Configuration.UI_MODE_NIGHT_MASK)==Configuration.UI_MODE_NIGHT_YES);}
 static LinearLayout stripe(Context c){LinearLayout row=new LinearLayout(c);for(int color:HostPalette.RAINBOW){View v=new View(c);v.setBackgroundColor(color);row.addView(v,new LinearLayout.LayoutParams(0,Math.round(3*c.getResources().getDisplayMetrics().density),1));}return row;}
}
