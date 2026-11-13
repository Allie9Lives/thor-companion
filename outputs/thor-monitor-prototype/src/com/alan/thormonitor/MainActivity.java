package com.alan.thormonitor;

import android.Manifest;
import android.app.*;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import org.json.JSONObject;
import java.util.*;
import java.util.concurrent.*;

public class MainActivity extends Activity {
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final ExecutorService reader=Executors.newSingleThreadExecutor();
    private final Telemetry telemetry=new Telemetry();
    private LinearLayout page;
    private SharedPreferences prefs;
    private int screen=0,step=0,recoveryReturn=0,renderedSetupStep=-1; // overview=0, setup=1, recovery=2, settings=3, insights=4
    private boolean dark,reading=false,repairing=false;
    private HostOverviewView overview;private HostBatteryInsightsView insights;
    private java.util.List<BatterySample> historyCache=java.util.Collections.emptyList();private long historyReadAt;private String historyError;private java.util.List<long[]> sleepCache=java.util.Collections.emptyList();
    private int renderedPairVersion=0;
    private int bg,card,ink,muted,border,accent,onAccent;
    private TextView ftpStatus;private Button ftpButton;
    private TextView status,health,controlsStatus,recoveryStatus,nearbyStatus,notificationStatus,batteryStatus;
    private EditText portField,codeField;
    private Button primary,backAction,nearbyAction,bluetoothAction,notificationAction,batteryAction;
    private final Runnable refresh=new Runnable(){public void run(){update();handler.postDelayed(this,2000);}};

    @Override public void onCreate(Bundle b) {
        super.onCreate(b);FindThor.recoverVolume(this);prefs=getSharedPreferences("monitor",0);
        screen=b!=null?b.getInt("screen"):prefs.getBoolean("setup_complete",false)?0:prefs.getInt("setup_screen",1);
        boolean oldFlow=prefs.contains("setup_step")&&prefs.getInt("setup_flow_version",1)<2;
        step=Math.max(0,Math.min(5,(b!=null?b.getInt("step"):prefs.getInt("setup_step",0))+(oldFlow?1:0)));
        prefs.edit().putInt("setup_flow_version",2).apply();
        try{ThorControls.socketName(this);}catch(Exception ignored){}
        recoveryReturn=b==null?0:b.getInt("recoveryReturn",0);
        build();
    }
    @Override public void onSaveInstanceState(Bundle b){b.putInt("screen",screen);b.putInt("step",step);b.putInt("recoveryReturn",recoveryReturn);super.onSaveInstanceState(b);}
    private int dp(float n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private boolean granted(String name){return checkSelfPermission(name)==PackageManager.PERMISSION_GRANTED;}
    private boolean nearby(){return granted(Manifest.permission.BLUETOOTH_CONNECT)&&granted(Manifest.permission.BLUETOOTH_ADVERTISE);}
    private boolean bluetooth(){try{return nearby()&&getSystemService(BluetoothManager.class).getAdapter().isEnabled();}catch(Exception e){return false;}}
    private boolean unrestricted(){return getSystemService(PowerManager.class).isIgnoringBatteryOptimizations(getPackageName());}
    private void colors(){
        HostPalette p=HostTheme.current(this);dark=p.dark;bg=p.bg;card=p.card;ink=p.ink;muted=p.muted;border=p.border;accent=p.accent;onAccent=p.onAccent;
    }
    private GradientDrawable shape(int color,int radius,boolean outline){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));if(outline)d.setStroke(dp(1),border);return d;}
    private TextView text(String value,int size,boolean bold){TextView t=new TextView(this);t.setText(value);t.setTextSize(size);t.setTextColor(ink);t.setFontFeatureSettings("tnum");t.setLineSpacing(dp(3),1);if(bold)t.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));return t;}
    private TextView body(LinearLayout parent,String value){TextView t=text(value,16,false);t.setTextColor(muted);parent.addView(t);return t;}
    private void gap(LinearLayout p,int h){Space s=new Space(this);p.addView(s,new LinearLayout.LayoutParams(1,dp(h)));}
    private ImageView glyph(String name,int size){ImageView view=new ImageView(this);view.setImageResource(getResources().getIdentifier("ic_host_"+name,"drawable",getPackageName()));view.setImageTintList(ColorStateList.valueOf(accent));view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);view.setLayoutParams(new LinearLayout.LayoutParams(dp(size),dp(size)));return view;}
    private String sectionIcon(String title){String t=title.toLowerCase(java.util.Locale.ROOT);if(t.contains("bluetooth"))return "bluetooth";if(t.contains("notification"))return "bell";if(t.contains("wi-fi")||t.contains("network")||t.contains("file"))return "wifi";if(t.contains("recover")||t.contains("pair")||t.contains("debug"))return "shield";if(t.contains("keyboard"))return "keyboard";if(t.contains("find"))return "locator";if(t.contains("appearance")||t.contains("color"))return "palette";if(t.contains("battery")||t.contains("background")||t.contains("overnight")||t.contains("cpu"))return "moon";return "options";}
    private void cardTitle(LinearLayout parent,String title){LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL);row.addView(glyph(sectionIcon(title),22));TextView label=text(title,18,true);label.setPadding(dp(10),0,0,0);row.addView(label,new LinearLayout.LayoutParams(0,-2,1));parent.addView(row);gap(parent,12);}
    private LinearLayout disclosure(String title,String icon,String summary){
        LinearLayout cardView=box(null),heading=new LinearLayout(this);heading.setGravity(Gravity.CENTER_VERTICAL);heading.setMinimumHeight(dp(48));heading.addView(glyph(icon,24));
        LinearLayout words=new LinearLayout(this);words.setOrientation(LinearLayout.VERTICAL);words.setPadding(dp(12),0,dp(12),0);words.addView(text(title,18,true));if(summary!=null){TextView subtitle=text(summary,14,false);subtitle.setTextColor(muted);words.addView(subtitle);}heading.addView(words,new LinearLayout.LayoutParams(0,-2,1));ImageView arrow=glyph("chevron",20);heading.addView(arrow);cardView.addView(heading);
        LinearLayout content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(0,dp(14),0,0);content.setVisibility(View.GONE);cardView.addView(content);heading.setFocusable(true);heading.setContentDescription(title+", show options");heading.setOnClickListener(v->{boolean open=content.getVisibility()!=View.VISIBLE;if(android.animation.ValueAnimator.areAnimatorsEnabled()){android.transition.AutoTransition transition=new android.transition.AutoTransition();transition.setDuration(160);android.transition.TransitionManager.beginDelayedTransition(page,transition);}content.setVisibility(open?View.VISIBLE:View.GONE);arrow.setRotation(open?180:0);heading.setContentDescription(title+(open?", hide options":", show options"));});return content;
    }
    private void setupHeading(String title,String subtitle,String symbol){
        TextView count=text((step+1)+" of 6",14,true);count.setTextColor(muted);count.setContentDescription("Setup step "+(step+1)+" of 6");page.addView(count);gap(page,10);
        LinearLayout progress=new LinearLayout(this);progress.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);for(int i=0;i<6;i++){View bar=new View(this);bar.setBackground(shape(i<=step?accent:border,4,false));LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,dp(3),1);if(i<5)lp.rightMargin=dp(6);progress.addView(bar,lp);}page.addView(progress);gap(page,22);
        LinearLayout hero=new LinearLayout(this);hero.setGravity(Gravity.TOP);ImageView icon=glyph(symbol,52);icon.setPadding(dp(12),dp(12),dp(12),dp(12));icon.setBackground(shape(card,16,true));hero.addView(icon);
        LinearLayout words=new LinearLayout(this);words.setOrientation(LinearLayout.VERTICAL);words.setPadding(dp(16),0,0,0);words.addView(text(title,28,true));TextView hint=text(subtitle,16,false);hint.setTextColor(muted);words.addView(hint);hero.addView(words,new LinearLayout.LayoutParams(0,-2,1));page.addView(hero);gap(page,24);
    }
    private void soundCredits(){new AlertDialog.Builder(this,dialogTheme()).setTitle("Sound credits").setMessage(android.text.Html.fromHtml("Tranquility by Helton Yan and Roberto Araujo.<br><br>Licensed under CC BY 4.0. Adapted with extraction, conversion, trimming, normalization and fades.<br><br><a href='https://heltonyan.itch.io/tranquility'>Sound pack</a> · <a href='https://creativecommons.org/licenses/by/4.0/'>License</a>",android.text.Html.FROM_HTML_MODE_LEGACY)).setPositiveButton("Done",null).show().<TextView>findViewById(android.R.id.message).setMovementMethod(android.text.method.LinkMovementMethod.getInstance());}
    private LinearLayout box(String title){
        LinearLayout b=new LinearLayout(this);b.setOrientation(LinearLayout.VERTICAL);b.setPadding(dp(20),dp(18),dp(20),dp(18));b.setBackground(shape(card,22,true));
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.bottomMargin=dp(14);page.addView(b,lp);
        if(title!=null)cardTitle(b,title);return b;
    }
    private Button button(LinearLayout parent,String label,boolean filled,Runnable action){
        Button b=new Button(this);b.setText(label);b.setAllCaps(false);b.setTextSize(16);b.setTypeface(Typeface.create("sans-serif-medium",0));b.setTextColor(filled?onAccent:ink);
        b.setBackground(shape(filled?accent:card,14,!filled));b.setStateListAnimator(null);b.setMinWidth(0);b.setPadding(dp(16),dp(12),dp(16),dp(12));b.setMinimumHeight(dp(50));
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.topMargin=dp(12);parent.addView(b,lp);b.setOnClickListener(v->action.run());return b;
    }
    private void toggle(LinearLayout parent,String title,String explanation,String key,boolean initial){
        LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL);TextView label=text(title,16,true);label.setPadding(0,0,dp(16),0);row.addView(label,new LinearLayout.LayoutParams(0,-2,1));
        Switch s=new Switch(this);s.setContentDescription(title);s.setChecked(prefs.getBoolean(key,initial));
        s.setThumbTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[]{}},new int[]{onAccent,ink}));
        s.setTrackTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[]{}},new int[]{accent,border}));row.addView(s);parent.addView(row);
        body(parent,explanation);gap(parent,8);
        s.setOnCheckedChangeListener((v,checked)->{prefs.edit().putBoolean(key,checked).apply();if(key.equals("files_enabled")){try{FileAccess.set(this,checked);}catch(Exception e){Toast.makeText(this,"Could not start file access",Toast.LENGTH_LONG).show();}}else if(key.equals("rest_keep_plugged"))MonitorService.restChanged();else if(key.equals("recover_controls"))Recovery.enable(this,checked);else if(key.equals("always_on")&&MonitorService.running)startMonitoring(false);});
    }
    private void build(){
        renderedPairVersion=Recovery.pairVersion;
        prefs.edit().putInt("setup_screen",screen).putInt("setup_step",step).apply();
        overview=null;insights=null;ftpStatus=null;ftpButton=null;
        colors();status=health=controlsStatus=recoveryStatus=nearbyStatus=notificationStatus=batteryStatus=null;portField=codeField=null;primary=backAction=nearbyAction=bluetoothAction=notificationAction=batteryAction=null;
        getWindow().setStatusBarColor(bg);getWindow().setNavigationBarColor(bg);getWindow().getDecorView().setSystemUiVisibility(dark?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        ScrollView scroll=new ScrollView(this);scroll.setBackgroundColor(bg);scroll.setClipToPadding(false);
        FrameLayout frame=new FrameLayout(this);scroll.addView(frame,new ScrollView.LayoutParams(-1,-2));
        page=new LinearLayout(this);page.setOrientation(LinearLayout.VERTICAL);page.setPadding(0,dp(20),0,dp(28));
        FrameLayout.LayoutParams pp=new FrameLayout.LayoutParams(Math.max(dp(240),Math.min(getResources().getDisplayMetrics().widthPixels-dp(40),dp(620))),-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);frame.addView(page,pp);
        LinearLayout header=new LinearLayout(this);header.setGravity(Gravity.CENTER_VERTICAL);
        View icon=new View(this){protected void onDraw(Canvas c){super.onDraw(c);Paint p=new Paint(3);p.setColor(accent);c.drawRoundRect(0,0,getWidth(),getHeight(),dp(12),dp(12),p);p.setColor(onAccent);p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(dp(1.6f));c.drawRoundRect(dp(10),dp(8),dp(30),dp(21),dp(3),dp(3),p);c.drawRoundRect(dp(10),dp(24),dp(30),dp(32),dp(2),dp(2),p);}};
        header.addView(icon,new LinearLayout.LayoutParams(dp(40),dp(40)));TextView name=text("Thor Monitor",20,true);name.setPadding(dp(12),0,0,0);header.addView(name,new LinearLayout.LayoutParams(0,-2,1));
        ImageButton theme=new ImageButton(this);theme.setImageResource(getResources().getIdentifier("ic_settings","drawable",getPackageName()));theme.setImageTintList(ColorStateList.valueOf(muted));theme.setBackgroundColor(Color.TRANSPARENT);theme.setContentDescription(screen==0?"Settings":"Appearance");theme.setOnClickListener(v->{if(screen==0){screen=3;build();}else appearance();});header.addView(theme,new LinearLayout.LayoutParams(dp(48),dp(48)));page.addView(header);if(HostTheme.current(this).rainbow){gap(page,14);page.addView(HostTheme.stripe(this));}gap(page,screen==1?20:26);
        if(screen==3||screen==4||screen==5){ImageButton back=new ImageButton(this);back.setImageResource(getResources().getIdentifier("ic_back","drawable",getPackageName()));back.setImageTintList(ColorStateList.valueOf(ink));back.setBackgroundColor(Color.TRANSPARENT);back.setContentDescription("Back to Overview");back.setOnClickListener(v->{screen=0;build();});LinearLayout.LayoutParams backSize=new LinearLayout.LayoutParams(dp(48),dp(48));backSize.rightMargin=dp(8);header.addView(back,0,backSize);}

        if(screen==1)setup();else if(screen==2)recovery();else if(screen==3)hostSettings();else if(screen==5)powerSettings();else if(screen==4){insights=new HostBatteryInsightsView(this);page.addView(insights);}else home();
        if(screen==1 && primary!=null) {
            page.removeView(primary);if(backAction!=null)page.removeView(backAction);
            FrameLayout root=new FrameLayout(this);root.setBackgroundColor(bg);
            scroll.setPadding(0,0,0,dp(16));scroll.setClipToPadding(true);frame.setPadding(0,0,0,dp(12));
            root.addView(scroll,new FrameLayout.LayoutParams(-1,-1));
            LinearLayout footer=new LinearLayout(this);footer.setGravity(Gravity.CENTER_VERTICAL);footer.setPadding(0,dp(10),0,dp(16));footer.setBackgroundColor(bg);
            if(backAction!=null){footer.addView(backAction,new LinearLayout.LayoutParams(dp(110),-2));Space space=new Space(this);footer.addView(space,new LinearLayout.LayoutParams(dp(12),1));}
            footer.addView(primary,new LinearLayout.LayoutParams(0,-2,1));
            footer.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or_,ob)->{FrameLayout.LayoutParams inset=(FrameLayout.LayoutParams)scroll.getLayoutParams();if(inset.bottomMargin!=footer.getHeight()){inset.bottomMargin=footer.getHeight();scroll.setLayoutParams(inset);}});
            root.addView(footer,new FrameLayout.LayoutParams(pp.width,-2,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL));setContentView(root);
        } else setContentView(scroll);
        if(screen==1&&renderedSetupStep>=0&&renderedSetupStep!=step&&android.animation.ValueAnimator.areAnimatorsEnabled()){page.setAlpha(0);page.setTranslationX(dp(step>renderedSetupStep?8:-8));page.animate().alpha(1).translationX(0).setDuration(180).setInterpolator(new android.view.animation.DecelerateInterpolator()).start();}
        renderedSetupStep=screen==1?step:-1;
        if(screen!=2)Recovery.stopPairingDiscovery(this);
        update();
    }
    private void home(){
        overview=new HostOverviewView(this,()->{screen=4;build();},()->startMonitoring(false));page.addView(overview);
    }
    private void hostSettings(){
        page.addView(text("Settings",28,true));gap(page,16);
        LinearLayout live=box(null);status=text("Checking connection…",22,true);live.addView(status);gap(live,6);health=body(live,"");controlsStatus=body(live,"");health.setVisibility(View.GONE);controlsStatus.setVisibility(View.GONE);
        primary=button(live,MonitorService.running?"Stop monitoring":"Start monitoring",true,()->{if(MonitorService.running){prefs.edit().putBoolean("monitor_wanted",false).apply();stopService(new Intent(this,MonitorService.class));handler.postDelayed(this::build,250);}else startMonitoring(false);});
        LinearLayout look=disclosure("Appearance","palette","Theme, color and app icon");button(look,"Theme",false,this::appearance);button(look,"Thor color & icon",false,this::colorPicker);
        LinearLayout background=disclosure("Monitoring","moon","Battery saving and automatic restart");button(background,"Battery saving",false,()->{screen=5;build();});
        toggle(background,"Start after restart","Resume after the Thor is unlocked.","start_on_boot",true);
        toggle(background,"Recover if interrupted","Keep monitoring available after app dismissal.","recover_dismissal",true);
        LinearLayout locator=disclosure("Find my Thor","locator","Stop sound panel");
        toggle(locator,"Stop panel over apps","Show a Stop button over games and other apps.","finder_overlay",true);
        body(locator,LocatorStopPanel.allowed(this)?"Overlay permission allowed":"Overlay permission needed");
        button(locator,"Overlay permission",false,()->startActivityForResult(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Uri.parse("package:"+getPackageName())),54));
        LinearLayout files=disclosure("Wi-Fi access","wifi","Network connection and shared folders");
        toggle(files,"Enable Wi-Fi access","Encrypted controls, screenshots and files. Existing VPN routes work too.","files_enabled",false);
        body(files,"Share selected folders or allow shared storage. Private app files stay protected.");
        button(files,"Shared storage permission",false,()->{prefs.edit().putBoolean("files_full",true).apply();startActivityForResult(new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,Uri.parse("package:"+getPackageName())),53);});
        body(files,android.os.Environment.isExternalStorageManager()?"Shared storage allowed":"Shared storage not allowed");
        toggle(files,"Share storage roots","Use internal storage and microSD from the top level.","files_full",false);
        button(files,"Choose internal folder",false,()->chooseFolder(51));body(files,FileAccess.folder(this,"internal").isEmpty()?"No internal folder selected":"Internal folder selected");
        button(files,"Choose microSD folder",false,()->chooseFolder(52));body(files,FileAccess.folder(this,"sd").isEmpty()?"No microSD folder selected":"microSD folder selected");
        button(files,"Revoke network access",false,()->{FileAccess.revoke(this);build();});
        LinearLayout ftp=disclosure("FTP server","wifi","Encrypted desktop transfers");
        ftpStatus=body(ftp,FtpAccess.running()?"Running · encrypted FTP":"Stopped");
        body(ftp,"Requires shared-storage access for Internal and microSD.");
        ftpButton=button(ftp,FtpAccess.running()?"Stop FTP server":"Start FTP server",false,()->{try{FtpAccess.command(this,FtpAccess.running()?"ftp_stop":"ftp_start","local");build();}catch(Exception e){Toast.makeText(this,e.getMessage(),Toast.LENGTH_LONG).show();}});
        button(ftp,"Connection details",false,()->{try{org.json.JSONObject j=FtpAccess.command(this,"ftp_status","local");if(!j.optBoolean("running")){Toast.makeText(this,"Start the FTP server first",Toast.LENGTH_LONG).show();return;}new AlertDialog.Builder(this).setTitle("FTP connection").setMessage("FTP · TLS/SSL Explicit encryption · Passive\n\nHost: "+j.optJSONArray("hosts")+"\nPort: "+j.optInt("port")+"\nUsername: thor\nPassword: "+j.optString("password")+"\n\nSHA-256: "+j.optString("pin")).setPositiveButton("Done",null).show();}catch(Exception e){Toast.makeText(this,"Connection details unavailable",Toast.LENGTH_LONG).show();}});
        LinearLayout restore=disclosure("Controls recovery","shield","Restore controls after a restart");recoveryStatus=body(restore,recoveryLabel());button(restore,"Recovery setup",false,()->openRecovery(false));
        LinearLayout keyboard=disclosure("Phone keyboard","keyboard","Type on the Thor from your phone");body(keyboard,"Enable Thor Remote Keyboard, then select it. Your usual keyboard remains available.");
        button(keyboard,"Enable keyboard",false,()->startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)));button(keyboard,"Select keyboard",false,()->getSystemService(android.view.inputmethod.InputMethodManager.class).showInputMethodPicker());
        button(page,"Review setup",false,()->{screen=1;step=0;build();});
        button(page,"Repair phone connection",false,this::repairPhone);
        Button forget=button(page,"Forget saved phone",false,()->{FileAccess.revoke(this);prefs.edit().remove("owner").putBoolean("monitor_wanted",false).apply();stopService(new Intent(this,MonitorService.class));Toast.makeText(this,"Phone forgotten. System Bluetooth pairing is unchanged.",Toast.LENGTH_LONG).show();handler.postDelayed(this::build,250);});forget.setTextColor(dark?0xFFFFA7A7:0xFFAD3030);
        gap(page,16);button(page,"Sound credits",false,this::soundCredits);
        LinearLayout about=disclosure("About","info","Version and credits");String version="";try{version=getPackageManager().getPackageInfo(getPackageName(),0).versionName;}catch(Exception ignored){}body(about,"Thor Monitor "+version);LinearLayout author=new LinearLayout(this);author.setGravity(Gravity.CENTER_VERTICAL);author.setPadding(0,dp(12),0,0);ImageView avatar=new ImageView(this);avatar.setImageResource(getResources().getIdentifier("author_avatar","drawable",getPackageName()));avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);android.graphics.drawable.GradientDrawable circle=new android.graphics.drawable.GradientDrawable();circle.setShape(android.graphics.drawable.GradientDrawable.OVAL);circle.setColor(card);avatar.setBackground(circle);avatar.setClipToOutline(true);author.addView(avatar,new LinearLayout.LayoutParams(dp(56),dp(56)));LinearLayout identity=new LinearLayout(this);identity.setOrientation(LinearLayout.VERTICAL);identity.setPadding(dp(14),0,0,0);identity.addView(text("Allie Stark",18,true));TextView handle=text("@Allie9Lives",14,false);handle.setTextColor(muted);identity.addView(handle);author.addView(identity,new LinearLayout.LayoutParams(0,-2,1));about.addView(author);body(about,"© 2026 Allie Stark (Allie9Lives)");button(about,"GitHub · Allie9Lives",false,()->{try{startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("https://github.com/Allie9Lives")));}catch(Exception e){Toast.makeText(this,"Couldn’t open GitHub",Toast.LENGTH_SHORT).show();}});
    }
    private void repairPhone(){
        if(!nearby()){Toast.makeText(this,"Allow Bluetooth access first",Toast.LENGTH_LONG).show();return;}
        List<BluetoothDevice> phones=MonitorService.repairCandidates();
        if(phones.isEmpty()){
            new AlertDialog.Builder(this).setTitle("Repair phone connection").setMessage("Keep monitoring on. Tap Reconnect on your phone, then return here within five minutes. Only bonded phones denied by this app can be approved.\n\nIf your phone says pairing information was removed, forget this Thor in the phone’s Bluetooth settings and connect again first.").setPositiveButton("OK",null).show();return;
        }
        String[] labels=new String[phones.size()];
        for(int i=0;i<phones.size();i++){BluetoothDevice d=phones.get(i);String name=d.getName();String address=d.getAddress();labels[i]=(name==null?"Phone":name)+" · "+address.substring(address.length()-5);}
        new AlertDialog.Builder(this).setTitle("Choose your phone").setItems(labels,(dialog,which)->{
            BluetoothDevice d=phones.get(which);
            new AlertDialog.Builder(this).setTitle("Authorize this phone?").setMessage("Approve only the phone you just used to reconnect. This replaces the saved phone and disables its Wi-Fi access. Link Wi-Fi access again from the companion after repair.").setNegativeButton("Cancel",null).setPositiveButton("Approve",(confirm,w)->{
                boolean ok=MonitorService.approvePhoneRepair(d.getAddress());
                Toast.makeText(this,ok?"Phone approved. Tap Reconnect on your phone.":"Request expired. Reconnect from the phone and try again.",Toast.LENGTH_LONG).show();build();
            }).show();
        }).setNegativeButton("Cancel",null).show();
    }
    private void saveRest(){MonitorService.restChanged();build();}
    private void restTime(String key,int initial){new TimePickerDialog(this,(v,h,m)->{int minute=h*60+m;String other=key.equals("rest_start")?"rest_end":"rest_start";if(minute==prefs.getInt(other,other.equals("rest_end")?360:1260)){Toast.makeText(this,"Start and restore times must differ",Toast.LENGTH_LONG).show();return;}prefs.edit().putInt(key,minute).apply();saveRest();},initial/60,initial%60,android.text.format.DateFormat.is24HourFormat(this)).show();}
    private String restDuration(int minutes){return minutes<60?minutes+(minutes==1?" minute":" minutes"):minutes%60==0?minutes/60+(minutes==60?" hour":" hours"):minutes/60+" h "+minutes%60+" min";}
    private void restDelay(){
        int[] values={30,60,120,180,240,360};String[] choices={"30 minutes","1 hour","2 hours","3 hours","4 hours","6 hours","Custom…"};
        new AlertDialog.Builder(this).setTitle("Pause after screens off").setItems(choices,(d,w)->{if(w<values.length){prefs.edit().putInt("rest_delay",values[w]).apply();saveRest();return;}
            EditText input=new EditText(this);input.setInputType(InputType.TYPE_CLASS_NUMBER);input.setText(String.valueOf(prefs.getInt("rest_delay",180)));input.setSelectAllOnFocus(true);input.setHint("Minutes (1–1440)");input.setContentDescription("Screens-off delay in minutes");
            AlertDialog dialog=new AlertDialog.Builder(this).setTitle("Custom delay in minutes").setView(input).setNegativeButton("Cancel",null).setPositiveButton("Save",null).create();
            dialog.setOnShowListener(v->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(save->{int minutes;try{minutes=Integer.parseInt(input.getText().toString());}catch(NumberFormatException e){input.setError("Enter 1–1440 minutes");return;}if(minutes<1||minutes>1440){input.setError("Enter 1–1440 minutes");return;}prefs.edit().putInt("rest_delay",minutes).apply();dialog.dismiss();saveRest();}));dialog.show();
        }).show();
    }
    private void powerSettings(){
        page.addView(text("Battery saving",28,true));gap(page,16);
        LinearLayout mode=box("CPU keep-alive");body(mode,"Keep readings available, or allow the Thor to sleep.");
        int selected=prefs.getInt("rest_mode",0);String[] labels={"Overnight · recommended","Always on · not recommended","Passive · allow sleep at any time"};
        for(int i=0;i<labels.length;i++){final int value=i;button(mode,(selected==i?"✓  ":"")+labels[i],selected==i,()->{prefs.edit().putInt("rest_mode",value).putBoolean("always_on",true).apply();saveRest();});}
        LinearLayout hours=box("Overnight schedule");body(hours,"Local time. Overnight pauses apply only on trusted Wi-Fi.");
        button(hours,"Night starts · "+PowerSaving.clock(prefs.getInt("rest_start",1260)),false,()->restTime("rest_start",prefs.getInt("rest_start",1260)));
        button(hours,"Restore keep-alive · "+PowerSaving.clock(prefs.getInt("rest_end",360)),false,()->restTime("rest_end",prefs.getInt("rest_end",360)));
        button(hours,"Pause after screens off · "+restDuration(prefs.getInt("rest_delay",180)),false,this::restDelay);
        body(hours,"Choose a preset or custom delay from 1 minute to 24 hours.");
        toggle(hours,"Keep awake while plugged in","Stay awake on external power, even at full charge.","rest_keep_plugged",false);
        body(hours,"Morning restore leaves screens off. Manual Stop stays off.");
        boolean exact=getSystemService(AlarmManager.class).canScheduleExactAlarms();body(hours,exact?"Exact alarms allowed":"Allow exact alarms for on-time restoration.");
        button(hours,"Alarms & reminders permission",false,()->startActivity(new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:"+getPackageName()))));
        LinearLayout networks=box("Trusted Wi-Fi");body(networks,"Only networks you add can pause overnight monitoring.");
        button(networks,"Trust current Wi-Fi",false,()->{Toast.makeText(this,"Checking current Wi-Fi…",Toast.LENGTH_SHORT).show();reader.execute(()->{JSONObject n=PowerSaving.network(this);handler.post(()->{if(isFinishing()||isDestroyed())return;if(!n.optBoolean("ok")){Toast.makeText(this,"Connect to Wi-Fi and finish Controls recovery first.",Toast.LENGTH_LONG).show();return;}new AlertDialog.Builder(this).setTitle("Trust "+n.optString("name")+"?").setMessage("Allow overnight pauses on this Wi-Fi network?").setNegativeButton("Cancel",null).setPositiveButton("Trust network",(d,w)->{java.util.Set<String> keys=new java.util.HashSet<>(prefs.getStringSet("rest_trusted",java.util.Collections.emptySet()));String key=n.optString("key");keys.add(key);prefs.edit().putStringSet("rest_trusted",keys).putString("rest_name_"+key,n.optString("name")).apply();saveRest();}).show();});});});
        java.util.Set<String> trusted=prefs.getStringSet("rest_trusted",java.util.Collections.emptySet());if(trusted.isEmpty())body(networks,"Add a network to enable overnight saving.");
        for(String key:trusted)button(networks,"Remove · "+prefs.getString("rest_name_"+key,"Trusted network"),false,()->{java.util.Set<String> keys=new java.util.HashSet<>(prefs.getStringSet("rest_trusted",java.util.Collections.emptySet()));keys.remove(key);prefs.edit().putStringSet("rest_trusted",keys).remove("rest_name_"+key).apply();saveRest();});
        LinearLayout about=disclosure("About battery saving","moon","Sleep, charging and trusted networks");body(about,"Pausing this app’s CPU keep-alive lets Android sleep. Other apps may keep it awake, and remote commands can be delayed. Manual Stop always stays off.");body(about,"Unplugging reapplies the current screens-off timer. Manual Allow deep sleep still works while plugged in.");body(about,"Trusted Wi-Fi is checked through Controls recovery. If the network cannot be verified, overnight pauses stay off. Wi-Fi and VPN settings are never changed.");
        button(page,"Back to Overview",false,()->{screen=0;build();});
    }
    private void setup(){
        String[] titles={"Choose your color","Connect with Bluetooth","Stay connected","Enable device controls","Optional features","Ready to connect"};
        String[] subtitles={"Match the theme and icon. Change them anytime.","Pair with your phone for readings and controls.","Allow alerts and reliable background monitoring.","Device controls, remote apps and screen capture.","Add these now, or return to Settings later.","Your Thor is ready for its companion."};
        String[] icons={"palette","bluetooth","bell","shield","options","phone"};setupHeading(titles[step],subtitles[step],icons[step]);
        if(step==0){
            LinearLayout colors=box(null);colorButtons(colors,null);
        }else if(step==1){
            LinearLayout b=box("Bluetooth");nearbyStatus=body(b,"");
            nearbyAction=button(b,"Allow Bluetooth access",true,this::requestNearby);
            bluetoothAction=button(b,"Turn on Bluetooth",false,()->{if(nearby())startActivity(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE));else requestNearby();});
        }else if(step==2){
            LinearLayout n=box("Notifications");body(n,"Monitoring status and Find my Thor alerts.");notificationStatus=body(n,"");notificationAction=button(n,"Allow notifications",false,this::requestNotifications);
            LinearLayout battery=box("Background access");body(battery,"Allow unrestricted battery use for reliable monitoring.");batteryStatus=body(battery,"");batteryAction=button(battery,"Battery permission",false,()->{try{startActivity(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,Uri.parse("package:"+getPackageName())));}catch(Exception e){startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));}});
            LinearLayout options=disclosure("Automatic restart","moon","Resume after restart or interruption");toggle(options,"Start after restart","Resume after the Thor is unlocked.","start_on_boot",true);toggle(options,"Recover if interrupted","Manual Stop always keeps monitoring off.","recover_dismissal",true);
        }else if(step==3){
            LinearLayout b=box("Controls recovery");body(b,"Pair once on trusted Wi-Fi. Controls restore automatically after a restart.");gap(b,10);recoveryStatus=body(b,recoveryLabel());button(b,"Set up controls",true,()->openRecovery(true));gap(b,10);body(b,"Optional. Bluetooth monitoring works without this step.");
        }else if(step==4){
            LinearLayout files=disclosure("Wi-Fi & files","wifi","Network controls, screenshots and file transfers");body(files,"Choose folders for phone transfers, or allow shared storage for both drives and desktop FTP access.");
            toggle(files,"Enable Wi-Fi access","Connect over Wi-Fi or your existing VPN.","files_enabled",false);
            button(files,"Shared storage permission",false,()->{prefs.edit().putBoolean("files_full",true).apply();startActivityForResult(new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,Uri.parse("package:"+getPackageName())),53);});
            button(files,"Choose internal folder",false,()->chooseFolder(51));button(files,"Choose microSD folder",false,()->chooseFolder(52));
            LinearLayout locator=disclosure("Find my Thor","locator","Show a Stop button over other apps");body(locator,"Allow the overlay to stop locator sounds from any app.");button(locator,"Overlay permission",false,()->startActivityForResult(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Uri.parse("package:"+getPackageName())),54));
            LinearLayout keyboard=disclosure("Phone keyboard","keyboard","Type from your phone");body(keyboard,"Enable Thor Remote Keyboard, then select it.");button(keyboard,"Enable keyboard",false,()->startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)));button(keyboard,"Select keyboard",false,()->getSystemService(android.view.inputmethod.InputMethodManager.class).showInputMethodPicker());
            LinearLayout saving=disclosure("Battery saving","moon","Set up overnight pauses after connecting");body(saving,"In Settings → Battery saving, add trusted Wi-Fi for overnight pauses. Default: three hours with screens off, 9 PM–6 AM. Monitoring stays awake until you add a trusted network.");
        }else{
            LinearLayout b=box("On your phone");setupInstruction(b,"1","Open Thor Companion.");setupInstruction(b,"2","Find your Thor and tap Connect.");setupInstruction(b,"3","Confirm pairing on both devices.");gap(b,10);body(b,"Keep the Thor open for the first connection.");
        }
        primary=button(page,step==5?"Start monitoring":"Continue",true,()->{if(step==1&&!nearby()){requestNearby();return;}if(step==1&&!bluetooth()){startActivity(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE));return;}if(step<5){step++;build();}else{prefs.edit().putBoolean("setup_complete",true).apply();startMonitoring(false);}});
        if(step>0)backAction=button(page,"Back",false,()->{step--;build();});
        if(prefs.getBoolean("setup_complete",false))button(page,"Back to Overview",false,()->{screen=0;build();});
    }
    private void setupInstruction(LinearLayout parent,String number,String value){LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(0,dp(8),0,dp(8));TextView index=text(number,14,true);index.setTextColor(accent);index.setGravity(Gravity.CENTER);index.setBackground(shape(bg,10,false));row.addView(index,new LinearLayout.LayoutParams(dp(32),dp(32)));TextView words=text(value,17,false);words.setPadding(dp(12),0,0,0);row.addView(words,new LinearLayout.LayoutParams(0,-2,1));parent.addView(row);}
    private void openRecovery(boolean fromSetup){recoveryReturn=fromSetup?1:0;screen=2;build();}
    private void leaveRecovery(){screen=recoveryReturn==1||!prefs.getBoolean("setup_complete",false)?1:0;build();}
    private String recoveryLabel(){
        if(!Recovery.state.equals("Set up automatic recovery"))return Recovery.state;
        if(Recovery.paired(this))return Recovery.enabled(this)?"Recovery enabled · starts with monitoring":"Automatic recovery is off";
        return "One-time pairing not completed";
    }
    private void recovery(){
        page.addView(text("Controls recovery",28,true));body(page,"One-time setup on trusted Wi-Fi.");gap(page,18);
        if(!Recovery.paired(this)||repairing){
            LinearLayout grant=box("1. Wireless debugging");body(grant,"Turn on Wireless debugging. Allow this network if Android asks.");button(grant,"Open wireless debugging",false,this::openWireless);
            LinearLayout pairing=box("2. Pair this Thor");body(pairing,"In Android settings, tap Pair device with pairing code. Enter the pairing port and code below.");
            portField=field(pairing,"Pairing port",5,false);portField.setId(1001);codeField=field(pairing,"Six-digit pairing code",6,true);codeField.setId(1002);
            button(pairing,"Pair controls",true,()->{String code=codeField.getText().toString().trim();int port=0;try{port=Integer.parseInt(portField.getText().toString().trim());}catch(Exception ignored){}Recovery.pair(this,port,code);codeField.setText("");});
        }else{LinearLayout paired=box("This Thor is paired");body(paired,"The pairing survives restarts and app updates.");button(paired,"Pair again",false,()->{repairing=true;build();});}
        LinearLayout readiness=box("Automatic recovery");recoveryStatus=body(readiness,recoveryLabel());
        toggle(readiness,"Restore controls automatically","Runs while monitoring and Wi-Fi are available.","recover_controls",false);
        button(readiness,"Retry now",false,()->Recovery.enable(this,true));body(readiness,"Unlock the Thor once after each restart.");
        LinearLayout help=disclosure("Setup help","shield","Developer options and pairing details");body(help,"Enable Developer options by tapping Build number seven times in Android settings. Use the port shown with the pairing code, not the connection port. Codes expire; request a new one if needed.");body(help,"When prompted, allow wireless debugging on your trusted network. Setup and recovery run on the Thor; no computer is required.");button(help,"Open wireless debugging",false,this::openWireless);
        button(page,recoveryReturn==1||!prefs.getBoolean("setup_complete",false)?"Back to setup":"Back to Overview",false,this::leaveRecovery);Recovery.watchPairing(this);
    }
    private EditText field(LinearLayout parent,String hint,int length,boolean secret){gap(parent,12);parent.addView(text(hint,14,true));EditText e=new EditText(this);e.setHint(secret?"6 digits":"From the pairing window");e.setContentDescription(hint);e.setSelectAllOnFocus(true);e.setTextSize(16);e.setTextColor(ink);e.setHintTextColor(muted);e.setBackgroundTintList(ColorStateList.valueOf(muted));e.setSingleLine(true);e.setInputType(InputType.TYPE_CLASS_NUMBER|(secret?InputType.TYPE_NUMBER_VARIATION_PASSWORD:0));e.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));e.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(length)});e.setSaveEnabled(!secret);e.setMinimumHeight(dp(52));parent.addView(e,new LinearLayout.LayoutParams(-1,-2));return e;}
    private void openWireless(){
        if(Recovery.permitted(this))try{Settings.Global.putInt(getContentResolver(),"adb_wifi_enabled",1);}catch(Exception ignored){}
        Recovery.watchPairing(this);
        Intent intent=new Intent("android.settings.WIRELESS_DEBUGGING_SETTINGS");
        if(intent.resolveActivity(getPackageManager())==null)intent=new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS);
        // The Thor can keep this form visible while the system pairing window is on its other screen.
        try {
            int bottom=-1;
            for(Display display:getSystemService(android.hardware.display.DisplayManager.class).getDisplays()){
                try{if(display.getDisplayId()!=0 && ((Integer)Display.class.getDeclaredMethod("getType").invoke(display))==1){bottom=display.getDisplayId();break;}}catch(Exception ignored){}
            }
            if(bottom<0){startActivity(intent);return;}
            ActivityOptions options=ActivityOptions.makeBasic();options.setLaunchDisplayId(bottom);startActivity(intent,options.toBundle());}
        catch(Exception e){startActivity(intent);}
    }
    private int dialogTheme(){return dark?android.R.style.Theme_DeviceDefault_Dialog_Alert:android.R.style.Theme_DeviceDefault_Light_Dialog_Alert;}
    private void appearance(){
        String[] names={"System default","Light","Dark","Clear Purple","Rainbow"},values={"system","light","dark","clearPurple","rainbow"};
        Dialog dialog=new Dialog(this);LinearLayout content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(22),dp(22),dp(22),dp(16));content.setBackground(shape(card,22,true));content.addView(text("Appearance",22,true));gap(content,6);
        for(int i=0;i<values.length;i++){final int choice=i;boolean selected=values[i].equals(prefs.getString("appearance","system"));button(content,(selected?"✓  ":"")+names[i],selected,()->{prefs.edit().putString("appearance",values[choice]).apply();dialog.dismiss();build();LocatorStopPanel.refresh(this);});}
        button(content,"Thor color & icon",false,()->{dialog.dismiss();colorPicker();});button(content,"Cancel",false,dialog::dismiss);ScrollView choices=new ScrollView(this);choices.addView(content);dialog.setContentView(choices);dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);dialog.show();dialog.getWindow().setLayout(Math.min(dp(400),getResources().getDisplayMetrics().widthPixels-dp(40)),-2);
    }
    private void colorButtons(LinearLayout parent,Dialog dialog){
        String selected=prefs.getString("thor_color","");
        for(int rowIndex=0;rowIndex<2;rowIndex++){
            LinearLayout row=new LinearLayout(this);parent.addView(row,new LinearLayout.LayoutParams(-1,-2));
            for(int column=0;column<2;column++){int i=rowIndex*2+column;final String value=ThorColor.VALUES[i];
                Button choice=button(row,(value.equals(selected)?"✓  ":"")+ThorColor.NAMES[i],value.equals(selected),()->{try{ThorAppearance.applyColor(this,value);if(dialog!=null)dialog.dismiss();build();LocatorStopPanel.refresh(this);}catch(Exception e){Toast.makeText(this,"Could not change the launcher icon. Your current icon is still available.",Toast.LENGTH_LONG).show();}});
                LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,-2,1);choice.setMinimumHeight(dp(48));choice.setPadding(dp(8),dp(8),dp(8),dp(8));lp.topMargin=dp(8);if(column==0)lp.rightMargin=dp(5);else lp.leftMargin=dp(5);choice.setLayoutParams(lp);
            }
        }
    }
    private void colorPicker(){
        Dialog dialog=new Dialog(this);LinearLayout content=new LinearLayout(this);content.setOrientation(LinearLayout.VERTICAL);content.setPadding(dp(22),dp(22),dp(22),dp(16));content.setBackground(shape(card,22,true));content.addView(text("Thor color & icon",22,true));gap(content,8);body(content,ThorColor.EXPLANATION);colorButtons(content,dialog);button(content,"Cancel",false,dialog::dismiss);ScrollView scroll=new ScrollView(this);scroll.addView(content);dialog.setContentView(scroll);dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);dialog.show();dialog.getWindow().setLayout(Math.min(dp(400),getResources().getDisplayMetrics().widthPixels-dp(40)),-2);
    }
    private void requestNotifications(){
        if(prefs.getBoolean("asked_notifications",false)&&!shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)){
            startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,getPackageName()));return;
        }
        prefs.edit().putBoolean("asked_notifications",true).apply();requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},11);
    }
    private void requestNearby(){
        List<String> missing=new ArrayList<>();for(String p:new String[]{Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_ADVERTISE})if(!granted(p))missing.add(p);
        if(missing.isEmpty()){Toast.makeText(this,"Bluetooth access is ready",Toast.LENGTH_SHORT).show();return;}
        if(prefs.getBoolean("asked_nearby",false)&&!shouldShowRequestPermissionRationale(missing.get(0))){startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:"+getPackageName())));return;}
        prefs.edit().putBoolean("asked_nearby",true).apply();requestPermissions(missing.toArray(new String[0]),10);
    }
    private void startMonitoring(boolean timed){
        if(!nearby()){screen=1;step=1;build();requestNearby();return;}
        if(!bluetooth()){startActivity(new Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE));return;}
        startForegroundService(new Intent(this,MonitorService.class).putExtra("active_test",timed).putExtra("always_on",prefs.getBoolean("always_on",false)));
        screen=0;handler.postDelayed(this::build,300);
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results){super.onRequestPermissionsResult(request,permissions,results);update();}
    private void update(){
        if(screen==2&&Recovery.paired(this)&&Recovery.pairVersion!=renderedPairVersion){repairing=false;build();return;}
        if((screen==0||screen==3)&&primary!=null)primary.setText(MonitorService.running?"Stop monitoring":"Start monitoring");
        if(nearbyAction!=null){nearbyAction.setVisibility(nearby()?View.GONE:View.VISIBLE);nearbyAction.setEnabled(!nearby());nearbyAction.setAlpha(nearby()?0.45f:1);nearbyAction.setText(nearby()?"Bluetooth allowed":"Allow nearby devices");}
        if(bluetoothAction!=null){bluetoothAction.setVisibility(nearby()&&!bluetooth()?View.VISIBLE:View.GONE);bluetoothAction.setEnabled(nearby()&&!bluetooth());bluetoothAction.setAlpha(bluetooth()?0.45f:1);bluetoothAction.setText(bluetooth()?"Bluetooth is on":"Turn on Bluetooth");}
        if(notificationAction!=null){boolean ready=granted(Manifest.permission.POST_NOTIFICATIONS);notificationAction.setVisibility(ready?View.GONE:View.VISIBLE);notificationAction.setEnabled(!ready);notificationAction.setAlpha(ready?0.45f:1);notificationAction.setText(ready?"Notifications allowed":"Allow notifications");}
        if(batteryAction!=null){batteryAction.setVisibility(unrestricted()?View.GONE:View.VISIBLE);batteryAction.setEnabled(!unrestricted());batteryAction.setAlpha(unrestricted()?0.45f:1);batteryAction.setText(unrestricted()?"Background access allowed":"Open battery permission");}
        if(ftpStatus!=null)ftpStatus.setText(FtpAccess.running()?"Running · encrypted FTP":"Stopped");if(ftpButton!=null)ftpButton.setText(FtpAccess.running()?"Stop FTP server":"Start FTP server");
        if(nearbyStatus!=null)nearbyStatus.setText(nearby()?(bluetooth()?"✓ Bluetooth ready":"Turn on Bluetooth to continue"):"Allow Bluetooth access to continue");
        if(notificationStatus!=null)notificationStatus.setText(granted(Manifest.permission.POST_NOTIFICATIONS)?"✓ Allowed":"Not allowed");
        if(batteryStatus!=null)batteryStatus.setText(unrestricted()?"✓ Allowed":"Permission needed");
        if(recoveryStatus!=null)recoveryStatus.setText(recoveryLabel());
        if(portField!=null&&portField.length()==0&&!portField.hasFocus()&&Recovery.pairingPort>0)portField.setText(String.valueOf(Recovery.pairingPort));
        if((status==null&&overview==null&&insights==null)||reading)return;reading=true;
        reader.execute(()->{
            JSONObject sample=telemetry.sample(this,0);boolean ready=controlsStatus!=null&&Recovery.helperReady(this);JSONObject focused=null;
            try{BatteryHistory store=BatteryHistory.get(this);store.record(sample);if(System.currentTimeMillis()-historyReadAt>=30000){historyReadAt=System.currentTimeMillis();historyCache=store.localSamples(System.currentTimeMillis()-7L*86400000);sleepCache=store.sleepEvents();historyError=null;}}catch(Exception e){historyError="Could not read local battery history.";}
            try{if(MonitorService.activity!=null)focused=MonitorService.activity.reply("host-ui");}catch(Exception ignored){}
            final JSONObject activity=focused;handler.post(()->{reading=false;if(isFinishing()||isDestroyed())return;
                if(overview!=null)overview.update(sample,historyCache,activity);
                if(insights!=null){insights.update(sample,historyCache);insights.setSleepEvents(sleepCache);insights.showError(historyError);}
                if(status!=null)status.setText(!MonitorService.running?"Monitoring stopped":!bluetooth()?"Bluetooth is off":MonitorService.connections>0?"Connected to your phone":"Ready for your phone");
                if(health!=null){health.setVisibility(View.VISIBLE);health.setText("Battery "+sample.optInt("battery_percent")+"% · UFS "+sample.optString("ufs_version","—")+"\n"+(MonitorService.connections==1?"1 phone connected":MonitorService.connections+" phones connected"));}
                if(controlsStatus!=null){controlsStatus.setVisibility(View.VISIBLE);controlsStatus.setText(ready?"Controls ready":"Controls need setup");}
            });
        });
    }

    private void chooseFolder(int request){Intent i=new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION|Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);startActivityForResult(i,request);}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==53||request==54){build();return;}if((request==51||request==52)&&result==RESULT_OK&&data!=null&&data.getData()!=null){try{FileAccess.choose(this,request==51?"internal":"sd",data.getData(),data.getFlags());build();}catch(Exception e){Toast.makeText(this,"Folder access was not granted",Toast.LENGTH_LONG).show();}}}
    @Override public void onResume(){super.onResume();handler.removeCallbacks(refresh);handler.post(refresh);}
    @Override public void onPause(){handler.removeCallbacks(refresh);super.onPause();}
    @Override public void onDestroy(){handler.removeCallbacksAndMessages(null);reader.shutdownNow();Recovery.stopPairingDiscovery(this);super.onDestroy();}
    @Override public void onBackPressed(){if(screen==3||screen==4||screen==5){screen=0;build();}else if(screen==2){leaveRecovery();}else if(screen==1&&step>0){step--;build();}else super.onBackPressed();}
}
