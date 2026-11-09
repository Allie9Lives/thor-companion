package com.alan.thormonitor;

import android.content.*;
import android.database.Cursor;
import android.database.sqlite.*;
import org.json.*;
import java.io.*;

/** Bounded measured history, independent of the phone connection. No app-usage estimates. */
final class BatteryHistory extends SQLiteOpenHelper {
    private static BatteryHistory instance;
    private long lastTime;
    private int lastPlug=-1,lastScreen=-1;
    private final Context app;
    private BatteryHistory(Context c){this(c,"battery-history.db");}
    private BatteryHistory(Context c,String name){super(c,name,null,2);app=c.getApplicationContext();}
    static synchronized BatteryHistory get(Context c){if(instance==null){instance=new BatteryHistory(c.getApplicationContext());instance.importDiagnostics();}return instance;}
    @Override public void onCreate(SQLiteDatabase db){db.execSQL("CREATE TABLE samples(t INTEGER PRIMARY KEY,p REAL NOT NULL,b INTEGER NOT NULL,temp REAL,v INTEGER,i INTEGER,q INTEGER,w REAL,s INTEGER NOT NULL)");db.execSQL("CREATE TABLE rest_events(t INTEGER PRIMARY KEY,c INTEGER NOT NULL)");}
    @Override public void onUpgrade(SQLiteDatabase db,int oldVersion,int newVersion){if(oldVersion<2)db.execSQL("CREATE TABLE IF NOT EXISTS rest_events(t INTEGER PRIMARY KEY,c INTEGER NOT NULL)");}
    private void importDiagnostics(){
        if(app.getSharedPreferences("monitor",0).getBoolean("history_imported",false))return;
        try(BufferedReader in=new BufferedReader(new FileReader(new File(app.getFilesDir(),"diagnostics.jsonl")))){
            String line;while((line=in.readLine())!=null){try{JSONObject entry=new JSONObject(line);JSONObject sample=entry.optJSONObject("data");if(entry.optString("event").startsWith("sample_")&&sample!=null)record(sample);}catch(Exception ignored){}}
        }catch(Exception ignored){}
        app.getSharedPreferences("monitor",0).edit().putBoolean("history_imported",true).apply();
    }
    synchronized void record(JSONObject j){
        long t=j.optLong("sampled_at_ms",0);double p=j.optDouble("battery_percent",Double.NaN);
        if(t<System.currentTimeMillis()-7L*86400000 || t>System.currentTimeMillis()+60000 || !Double.isFinite(p)||p<0||p>100)return;
        int plugged=j.optInt("plugged_code",0),screen=j.optBoolean("interactive",false)?1:0;
        if(lastTime==0){try(Cursor c=getReadableDatabase().rawQuery("SELECT t,b,s FROM samples ORDER BY t DESC LIMIT 1",null)){if(c.moveToFirst()){lastTime=c.getLong(0);lastPlug=c.getInt(1);lastScreen=c.getInt(2);}}}
        if(t<lastTime-60000)lastTime=0;
        if(t>=lastTime && t-lastTime<300000 && plugged==lastPlug && screen==lastScreen)return;
        ContentValues row=new ContentValues();row.put("t",t);row.put("p",Math.round(p*10)/10.0);row.put("b",plugged);row.put("s",screen);
        metric(row,"temp",j,"battery_temperature_c",-40,100);metric(row,"v",j,"battery_voltage_mv",0,20000);
        metric(row,"i",j,"current_ua_raw",-20000000,20000000);metric(row,"q",j,"charge_counter_uah",0,20000000);metric(row,"w",j,"input_watts",0,480);
        getWritableDatabase().insertWithOnConflict("samples",null,row,SQLiteDatabase.CONFLICT_REPLACE);
        getWritableDatabase().delete("samples","t<?",new String[]{String.valueOf(System.currentTimeMillis()-7L*86400000)});
        getWritableDatabase().execSQL("DELETE FROM samples WHERE t NOT IN (SELECT t FROM samples ORDER BY t DESC LIMIT 10000)");
        lastTime=t;lastPlug=plugged;lastScreen=screen;
    }
    private static void metric(ContentValues row,String key,JSONObject source,String field,double min,double max){
        double value=source.optDouble(field,Double.NaN);if(Double.isFinite(value)&&value>=min&&value<=max)row.put(key,Math.round(value*100)/100.0);else row.putNull(key);
    }
    synchronized java.util.List<BatterySample> localSamples(long since){
        java.util.List<BatterySample> rows=new java.util.ArrayList<>();long cutoff=Math.max(since,System.currentTimeMillis()-7L*86400000);
        try(Cursor c=getReadableDatabase().rawQuery("SELECT t,p,b,s,temp FROM samples WHERE t>=? ORDER BY t LIMIT 10000",new String[]{String.valueOf(cutoff)})){
            while(c.moveToNext())rows.add(new BatterySample(c.getLong(0),c.getDouble(1),c.getInt(2)!=0,c.getInt(3)==1,c.isNull(4)?null:c.getDouble(4)));
        }return rows;
    }
    synchronized void sleepEvent(long t,int code){
        try{try(Cursor c=getReadableDatabase().rawQuery("SELECT c FROM rest_events ORDER BY t DESC LIMIT 1",null)){if(c.moveToFirst()&&c.getInt(0)==code)return;}
        ContentValues v=new ContentValues();v.put("t",t);v.put("c",code);getWritableDatabase().insertWithOnConflict("rest_events",null,v,SQLiteDatabase.CONFLICT_REPLACE);getWritableDatabase().delete("rest_events","t<?",new String[]{String.valueOf(System.currentTimeMillis()-7L*86400000)});
        getWritableDatabase().execSQL("DELETE FROM rest_events WHERE t NOT IN (SELECT t FROM rest_events ORDER BY t DESC LIMIT 2000)");}catch(Exception ignored){}
    }
    synchronized java.util.List<long[]> sleepEvents(){java.util.List<long[]> out=new java.util.ArrayList<>();try(Cursor c=getReadableDatabase().rawQuery("SELECT t,c FROM rest_events ORDER BY t LIMIT 2000",null)){while(c.moveToNext())out.add(new long[]{c.getLong(0),c.getInt(1)});}return out;}
    synchronized JSONObject sleepPage(long after,String id)throws Exception{
        if(after<0||after>System.currentTimeMillis()+60000)throw new IllegalArgumentException("Invalid history cursor");JSONArray rows=new JSONArray();long next=after;boolean more=false;
        try(Cursor c=getReadableDatabase().rawQuery("SELECT t,c FROM rest_events WHERE t>? ORDER BY t LIMIT 9",new String[]{String.valueOf(after)})){while(c.moveToNext()){if(rows.length()==8){more=true;break;}rows.put(new JSONArray().put(c.getLong(0)).put(c.getInt(1)));next=c.getLong(0);}}
        return new JSONObject().put("v",1).put("ack",id).put("error","").put("sleep_events",rows).put("next",next).put("more",more);
    }
    synchronized JSONObject page(long after,String range,String id)throws Exception{
        if(after<0 || after>System.currentTimeMillis()+60000 || !(range.equals("24h")||range.equals("7d")))throw new IllegalArgumentException("Invalid history range");
        long since=System.currentTimeMillis()-(range.equals("7d")?7L:1L)*86400000;
        JSONArray rows=new JSONArray();long next=after;boolean more=false;
        try(Cursor c=getReadableDatabase().rawQuery("SELECT t,p,b,temp,v,i,q,w,s FROM samples WHERE t>=? AND t>? ORDER BY t LIMIT 5",new String[]{String.valueOf(since),String.valueOf(after)})){
            while(c.moveToNext()){
                if(rows.length()==4){more=true;break;}
                JSONArray row=new JSONArray();for(int i=0;i<9;i++){if(c.isNull(i))row.put(JSONObject.NULL);else if(i==0)row.put(c.getLong(i));else if(i==2||i==4||i==5||i==6||i==8)row.put(c.getLong(i));else row.put(c.getDouble(i));}
                rows.put(row);next=c.getLong(0);
            }
        }
        JSONObject reply=new JSONObject().put("v",1).put("ack",id).put("error","").put("history",rows).put("next",next).put("more",more);
        if(reply.toString().getBytes("UTF-8").length>500)throw new IllegalStateException("History page too large");
        return reply;
    }
}
