package com.alan.thormonitor;
/** Cosmetic shell choices only; this never changes model detection or device controls. */
final class ThorColor {
 static final String[] VALUES={"black","white","clearPurple","rainbow"};
 static final String[] NAMES={"Black","White","Clear Purple","Rainbow"};
 static final String[] ALIASES={"LauncherBlack","LauncherWhite","LauncherPurple","LauncherRainbow"};
 static int index(String value){for(int i=0;i<VALUES.length;i++)if(VALUES[i].equals(value))return i;return -1;}
 static String theme(String value){switch(value){case "black":return "dark";case "white":return "light";case "clearPurple":return "clearPurple";case "rainbow":return "rainbow";default:throw new IllegalArgumentException("Unknown Thor color");}}
 static final String EXPLANATION="Matches the host theme and app icon to your Thor. Change either later in Appearance.";
}
