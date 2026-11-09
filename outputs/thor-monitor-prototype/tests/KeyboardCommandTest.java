package com.alan.thormonitor;
public class KeyboardCommandTest {
    static void rejected(Runnable r) { try { r.run(); throw new AssertionError("Accepted invalid input"); } catch(IllegalArgumentException expected) {} }
    public static void main(String[] args) {
        KeyboardCommand.text("Thor — café 👾 中文\n\t'$()`;%s");
        KeyboardCommand.text(new String(new char[120]).replace('\0','a'));
        rejected(()->KeyboardCommand.text(""));
        rejected(()->KeyboardCommand.text(new String(new char[121]).replace('\0','a')));
        rejected(()->KeyboardCommand.text("x\u0000y"));
        rejected(()->KeyboardCommand.text("\uD800"));
        rejected(()->KeyboardCommand.text("\uDC00"));
        for(String key:new String[]{"enter","backspace","tab","left","right","up","down"}) KeyboardCommand.key(key);
        rejected(()->KeyboardCommand.key("shell"));
        rejected(()->KeyboardCommand.key("home"));
        System.out.println("Keyboard validation tests passed: Unicode, size, control characters, allowlisted keys.");
    }
}
