package com.alan.thormonitor;
import java.util.*;
public class FocusedDisplaysTest {
 public static void main(String[] args){
  String dump="FocusedApplications:\n displayId=4, name='ActivityRecord{abc u0 com.example.bottom/.Main}'\n displayId=0, name='ActivityRecord{def u0 com.example.top/.Main}'\nFocusedWindows:\n stale\nFocusedApplications:\n displayId=0, name='ActivityRecord{old u0 com.example.stale/.Main}'\nFocusedWindows:";
  Map<Integer,String> result=FocusedDisplays.parse(dump);if(!"com.example.top".equals(result.get(0))||!"com.example.bottom".equals(result.get(4))||result.keySet().iterator().next()!=0)throw new AssertionError("Screen order or stale dispatcher parse");
  if(!FocusedDisplays.parse("no focused applications").isEmpty())throw new AssertionError();
  System.out.println("Top/bottom order and stale dispatcher isolation passed.");
 }
}
