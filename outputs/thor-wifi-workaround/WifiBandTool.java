import android.net.wifi.WifiConfiguration;
import android.os.*;
import java.lang.reflect.Method;
import org.json.JSONObject;
import java.util.List;

/** Setup-only, authorized ADB utility. Changes only the chosen saved profile's BSSID. */
public final class WifiBandTool {
 static Object invoke(Object target,String name,Class<?>[] types,Object... args)throws Exception {
  Method m=target.getClass().getMethod(name,types);m.setAccessible(true);return m.invoke(target,args);
 }
 public static void main(String[] args)throws Exception {
  if(android.os.Process.myUid()!=2000||args.length<2)throw new SecurityException("Authorized ADB shell required");
  String mode=args[0];int id=Integer.parseInt(args[1]);
  IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getDeclaredMethod("getService",String.class).invoke(null,"wifi");
  Object manager=Class.forName("android.net.wifi.IWifiManager$Stub").getDeclaredMethod("asInterface",IBinder.class).invoke(null,binder);
  Object slice=invoke(manager,"getConfiguredNetworks",new Class[]{String.class,String.class,boolean.class},"com.android.shell",null,false);
  List<?> configs=(List<?>)invoke(slice,"getList",new Class[]{});
  WifiConfiguration found=null;
  for(Object entry:configs){WifiConfiguration config=(WifiConfiguration)entry;if(config.networkId==id){found=config;break;}}
  if(found==null)throw new IllegalStateException("Saved network not found");
  if(mode.equals("inspect")){System.out.println(new JSONObject().put("network_id",id).put("bssid",found.BSSID==null?JSONObject.NULL:found.BSSID));return;}
  if(mode.equals("pin")){
   if(args.length!=3||!args[2].matches("(?i)[0-9a-f]{2}(:[0-9a-f]{2}){5}"))throw new IllegalArgumentException("Expected access point identifier");
   found.BSSID=args[2];
  }else if(mode.equals("clear")){found.BSSID=null;}else throw new IllegalArgumentException("Unsupported operation");
  int result=(Integer)invoke(manager,"addOrUpdateNetwork",new Class[]{WifiConfiguration.class,String.class,Bundle.class},found,"com.android.shell",new Bundle());
  if(result!=id)throw new IllegalStateException("Saved-network update rejected");
  boolean enabled=(Boolean)invoke(manager,"enableNetwork",new Class[]{int.class,boolean.class,String.class},id,true,"com.android.shell");
  if(!enabled)throw new IllegalStateException("Reconnect request rejected");
  System.out.println(new JSONObject().put("updated",true).put("network_id",id).put("pinned",found.BSSID!=null));
 }
}
