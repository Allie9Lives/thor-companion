package com.alan.thormonitor;
import java.util.*;import java.util.regex.*;
final class FocusedDisplays {
 static Map<Integer,String> parse(String input){
  Map<Integer,String> result=new TreeMap<>();int begin=input.indexOf("FocusedApplications:");if(begin<0)return result;int end=input.indexOf("FocusedWindows:",begin);if(end<0)return result;
  Matcher app=Pattern.compile("displayId=(\\d+), name='ActivityRecord\\{[^ ]+ u\\d+ ([A-Za-z0-9_.]+)/").matcher(input.substring(begin,end));
  while(app.find()){int display=Integer.parseInt(app.group(1));if(display==0||display==4)result.put(display,app.group(2));}return result;
 }
}
