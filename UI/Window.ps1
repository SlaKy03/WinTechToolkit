# Native helpers for the custom title bar: Windows 11 rounded corners, border colour
# and Snap Layouts on the maximize button.

if (-not ('WTWindowHelper' -as [type])) {
    $refs = @([System.Windows.Window].Assembly.Location, [System.Windows.UIElement].Assembly.Location,
        [System.Windows.DependencyObject].Assembly.Location, [System.Xaml.XamlReader].Assembly.Location)
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

public static class WTWindowHelper {
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    // DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND; fails before Windows 11
    public static bool RoundCorners(IntPtr hwnd) {
        int value = 2;
        try { return DwmSetWindowAttribute(hwnd, 33, ref value, 4) == 0; } catch { return false; }
    }

    [DllImport("user32.dll")]
    static extern int GetSystemMetrics(int index);

    // A maximized window overflows the screen by the resize frame plus the padded border
    // (SM_CXSIZEFRAME + SM_CXPADDEDBORDER): the content is inset by the same amount.
    public static Thickness MaximizedInset(Visual visual) {
        int padded = GetSystemMetrics(92);
        double x = GetSystemMetrics(32) + padded, y = GetSystemMetrics(33) + padded;
        PresentationSource source = PresentationSource.FromVisual(visual);
        if (source != null && source.CompositionTarget != null) {
            Matrix m = source.CompositionTarget.TransformFromDevice;
            x *= m.M11;
            y *= m.M22;
        }
        return new Thickness(x, y, x, y);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct FLASHWINFO { public int cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
    [DllImport("user32.dll")]
    static extern bool FlashWindowEx(ref FLASHWINFO info);

    // Flashes the taskbar button until the window comes to the foreground (FLASHW_TRAY | FLASHW_TIMERNOFG)
    public static void FlashTaskbar(IntPtr hwnd) {
        FLASHWINFO f = new FLASHWINFO();
        f.cbSize = Marshal.SizeOf(typeof(FLASHWINFO));
        f.hwnd = hwnd;
        f.dwFlags = 0x2 | 0xC;
        try { FlashWindowEx(ref f); } catch { }
    }

    // DWMWA_BORDER_COLOR (COLORREF 0x00BBGGRR)
    public static void SetBorderColor(IntPtr hwnd, Color color) {
        int value = color.R | (color.G << 8) | (color.B << 16);
        try { DwmSetWindowAttribute(hwnd, 34, ref value, 4); } catch { }
    }
}

// Table cells cut with "..." show the whole text in a tooltip: the tooltip of the TextBlocks
// marked with Tag "TrimTip" opens only when the text does not fit.
public static class WTTrimToolTip {
    static bool registered;

    public static void Register() {
        if (registered) return;
        registered = true;
        EventManager.RegisterClassHandler(typeof(TextBlock), FrameworkElement.ToolTipOpeningEvent, new ToolTipEventHandler(OnOpening));
    }

    static void OnOpening(object sender, ToolTipEventArgs e) {
        TextBlock tb = sender as TextBlock;
        if (tb == null || !"TrimTip".Equals(tb.Tag)) return;
        if (string.IsNullOrEmpty(tb.Text)) { e.Handled = true; return; }
        FormattedText ft = new FormattedText(tb.Text, System.Globalization.CultureInfo.CurrentUICulture, tb.FlowDirection,
            new Typeface(tb.FontFamily, tb.FontStyle, tb.FontWeight, tb.FontStretch), tb.FontSize, Brushes.Black,
            VisualTreeHelper.GetDpi(tb).PixelsPerDip);
        if (ft.WidthIncludingTrailingWhitespace <= tb.ActualWidth + 1) e.Handled = true;
    }
}

// The maximize button area is reported to Windows as HTMAXBUTTON, so that Windows 11
// shows Snap Layouts on hover. Windows then sends non-client messages instead of the
// WPF mouse events: hover and click are handled here.
public class WTSnapLayoutHook {
    const int WM_NCHITTEST = 0x84, WM_NCMOUSEMOVE = 0xA0, WM_NCLBUTTONDOWN = 0xA1, WM_NCLBUTTONUP = 0xA2,
        WM_NCLBUTTONDBLCLK = 0xA3, WM_NCMOUSELEAVE = 0x2A2, HTMAXBUTTON = 9;
    const uint TME_LEAVE = 0x2, TME_NONCLIENT = 0x10;

    [StructLayout(LayoutKind.Sequential)]
    struct TRACKMOUSEEVENT { public int cbSize; public uint dwFlags; public IntPtr hwndTrack; public uint dwHoverTime; }
    [DllImport("user32.dll")]
    static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT tme);

    readonly Window window;
    readonly Button button;
    readonly string hoverBrushKey;
    bool hover;

    public WTSnapLayoutHook(Window window, Button button, string hoverBrushKey) {
        this.window = window;
        this.button = button;
        this.hoverBrushKey = hoverBrushKey;
    }

    public void Attach() {
        HwndSource source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle);
        if (source != null) source.AddHook(WndProc);
    }

    bool IsOverButton(IntPtr lParam) {
        if (!button.IsVisible || PresentationSource.FromVisual(button) == null) return false;
        long lp = lParam.ToInt64();
        int x = (short)(lp & 0xFFFF), y = (short)((lp >> 16) & 0xFFFF);
        Point topLeft = button.PointToScreen(new Point(0, 0));
        Point bottomRight = button.PointToScreen(new Point(button.ActualWidth, button.ActualHeight));
        return x >= topLeft.X && x < bottomRight.X && y >= topLeft.Y && y < bottomRight.Y;
    }

    void SetHover(bool on, IntPtr hwnd) {
        if (hover == on) return;
        hover = on;
        if (on) {
            button.SetResourceReference(Control.BackgroundProperty, hoverBrushKey);
            TRACKMOUSEEVENT tme = new TRACKMOUSEEVENT();
            tme.cbSize = Marshal.SizeOf(typeof(TRACKMOUSEEVENT));
            tme.dwFlags = TME_LEAVE | TME_NONCLIENT;
            tme.hwndTrack = hwnd;
            TrackMouseEvent(ref tme);
        } else {
            button.ClearValue(Control.BackgroundProperty);
        }
    }

    IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) {
        switch (msg) {
            case WM_NCHITTEST:
                if (IsOverButton(lParam)) { handled = true; return new IntPtr(HTMAXBUTTON); }
                if (hover) SetHover(false, hwnd);
                break;
            case WM_NCMOUSEMOVE:
                SetHover(wParam.ToInt64() == HTMAXBUTTON, hwnd);
                break;
            case WM_NCMOUSELEAVE:
                SetHover(false, hwnd);
                break;
            case WM_NCLBUTTONDOWN:
            case WM_NCLBUTTONDBLCLK:
                // default handling would draw a classic caption button
                if (wParam.ToInt64() == HTMAXBUTTON) { handled = true; }
                break;
            case WM_NCLBUTTONUP:
                if (wParam.ToInt64() == HTMAXBUTTON) {
                    handled = true;
                    SetHover(false, hwnd);
                    window.WindowState = window.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                }
                break;
        }
        return IntPtr.Zero;
    }
}
'@
}
