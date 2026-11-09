package com.alan.thormonitor;

import java.nio.charset.StandardCharsets;

/** Validates input data; text is never interpreted as a shell command. */
final class KeyboardCommand {
    static void text(String value) {
        if (value == null || value.isEmpty() || value.getBytes(StandardCharsets.UTF_8).length > 120)
            throw new IllegalArgumentException("Text must contain 1–120 UTF-8 bytes");
        for (int i=0;i<value.length();i++) {
            char c=value.charAt(i);
            if (c<32 && c!='\n' && c!='\r' && c!='\t' || c==127)
                throw new IllegalArgumentException("Unsupported text character");
            if (Character.isHighSurrogate(c)) {
                if (++i>=value.length() || !Character.isLowSurrogate(value.charAt(i)))
                    throw new IllegalArgumentException("Invalid Unicode text");
            } else if (Character.isLowSurrogate(c)) throw new IllegalArgumentException("Invalid Unicode text");
        }
    }
    static void key(String value) {
        if (!("backspace".equals(value) || "enter".equals(value) || "tab".equals(value) ||
              "left".equals(value) || "right".equals(value) || "up".equals(value) || "down".equals(value)))
            throw new IllegalArgumentException("Unsupported keyboard key");
    }
}
