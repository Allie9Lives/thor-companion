package com.alan.thormonitor;

/** Only the port is used; recovery always connects to this Thor's loopback. */
final class PairingInput {
 static int port(String value){
  String text=value==null?"":value.trim();int colon=text.lastIndexOf(':');
  if(colon>=0)text=text.substring(colon+1);
  if(!text.matches("[0-9]{1,5}"))return 0;
  int port=Integer.parseInt(text);return port>0&&port<=65535?port:0;
 }
}
