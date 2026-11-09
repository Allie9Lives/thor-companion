package com.alan.thormonitor;

import android.app.KeyguardManager;
import android.content.*;
import android.inputmethodservice.InputMethodService;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.view.inputmethod.*;
import android.widget.*;
import java.util.concurrent.*;

/** Optional IME. Receives only authenticated BLE commands through ThorControls. */
public final class RemoteKeyboard extends InputMethodService {
    private static volatile RemoteKeyboard instance;
    private volatile boolean editing, inputViewActive;
    static boolean selected(Context c) {
        String current=Settings.Secure.getString(c.getContentResolver(),Settings.Secure.DEFAULT_INPUT_METHOD);
        return current!=null && new ComponentName(c,RemoteKeyboard.class).equals(ComponentName.unflattenFromString(current));
    }
    static boolean focused() { RemoteKeyboard k=instance;return k!=null && k.editing && k.inputViewActive; }
    @Override public void onCreate() { super.onCreate();instance=this; }
    @Override public void onStartInput(EditorInfo info,boolean restarting) { super.onStartInput(info,restarting);editing=true; }
    @Override public void onStartInputView(EditorInfo info,boolean restarting) { super.onStartInputView(info,restarting);inputViewActive=true; }
    @Override public void onFinishInputView(boolean finishingInput) { inputViewActive=false;super.onFinishInputView(finishingInput); }
    @Override public void onUnbindInput() { editing=false;inputViewActive=false;super.onUnbindInput(); }
    @Override public void onFinishInput() { editing=false;inputViewActive=false;super.onFinishInput(); }
    @Override public void onDestroy() { editing=false;if(instance==this)instance=null;super.onDestroy(); }
    @Override public boolean onEvaluateFullscreenMode() { return false; }
    @Override public View onCreateInputView() {
        LinearLayout view=new LinearLayout(this);view.setOrientation(LinearLayout.VERTICAL);
        int pad=(int)(16*getResources().getDisplayMetrics().density);view.setPadding(pad,pad,pad,pad);
        TextView label=new TextView(this);label.setText("Type from Thor Companion on your phone");label.setTextSize(18);view.addView(label);
        Button change=new Button(this);change.setText("Switch keyboard");change.setOnClickListener(v->getSystemService(InputMethodManager.class).showInputMethodPicker());view.addView(change);
        return view;
    }
    static void input(Context c,String command,String value) throws Exception {
        if (command.equals("text")) KeyboardCommand.text(value); else KeyboardCommand.key(value);
        if (!selected(c)) throw new IllegalStateException("Select Thor Remote Keyboard in Thor Monitor first");
        // No remote typing into the lock screen, and no delayed replay after unlock.
        if (c.getSystemService(KeyguardManager.class).isKeyguardLocked() || !c.getSystemService(PowerManager.class).isInteractive())
            throw new IllegalStateException("Open and unlock the Thor to type");
        FutureTask<Void> task=new FutureTask<>(()->{
            RemoteKeyboard k=instance;
            if(k==null || !focused() || !k.isInputViewShown() || k.getCurrentInputConnection()==null ||
                k.getCurrentInputEditorInfo()==null || k.getCurrentInputEditorInfo().inputType==android.text.InputType.TYPE_NULL)
                throw new IllegalStateException("Tap a text field on the Thor first");
            InputConnection ic=k.getCurrentInputConnection();
            if(command.equals("text")) {
                if(!ic.commitText(value,1)) throw new IllegalStateException("The focused app did not accept text");
            } else if(value.equals("enter")) {
                if(!k.sendDefaultEditorAction(true)) {
                    if(!ic.commitText("\n",1)) throw new IllegalStateException("The focused app did not accept Enter");
                }
            } else {
                int code=value.equals("backspace")?KeyEvent.KEYCODE_DEL:value.equals("tab")?KeyEvent.KEYCODE_TAB:
                    value.equals("left")?KeyEvent.KEYCODE_DPAD_LEFT:value.equals("right")?KeyEvent.KEYCODE_DPAD_RIGHT:
                    value.equals("up")?KeyEvent.KEYCODE_DPAD_UP:KeyEvent.KEYCODE_DPAD_DOWN;
                k.sendDownUpKeyEvents(code);
            }
            return null;
        });
        if(Looper.myLooper()==Looper.getMainLooper())task.run();else new Handler(Looper.getMainLooper()).post(task);
        try { task.get(2,TimeUnit.SECONDS); }
        catch(TimeoutException e) { task.cancel(false);throw new IllegalStateException("Keyboard timed out. Check the Thor before sending again"); }
        catch(ExecutionException e) { throw new IllegalStateException(e.getCause().getMessage()); }
    }
}
