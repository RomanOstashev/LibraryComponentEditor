using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Interop;

namespace LibraryComponentEditor
{
    public partial class EditorWindow : Window
    {
        private const uint NoZOrder = 0x0004;
        private const uint NoActivate = 0x0010;
        private WindowState _stateBeforeMinimize = WindowState.Normal;

        public EditorWindow()
        {
            InitializeComponent();
        }

        internal void ShowOnHostMonitor(IntPtr hostWindow)
        {
            var area = Screen.FromHandle(hostWindow).WorkingArea;
            var handle = new WindowInteropHelper(this).EnsureHandle();

            // Set the restore bounds in screen pixels before maximizing the unowned window.
            // This also works for monitors left of the primary display or with different DPI.
            if (!SetWindowPos(handle, IntPtr.Zero, area.Left + area.Width / 8, area.Top + area.Height / 8,
                area.Width * 3 / 4, area.Height * 3 / 4, NoZOrder | NoActivate))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            WindowState = WindowState.Maximized;
            Show();
        }

        protected override void OnStateChanged(EventArgs args)
        {
            base.OnStateChanged(args);
            if (WindowState != WindowState.Minimized)
                _stateBeforeMinimize = WindowState;
        }

        internal void BringToFront()
        {
            if (WindowState == WindowState.Minimized)
                WindowState = _stateBeforeMinimize;
            Activate();
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y,
            int width, int height, uint flags);
    }
}
