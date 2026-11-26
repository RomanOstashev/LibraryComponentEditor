using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using Renga;

namespace LibraryComponentEditor
{
    public sealed class Plugin : IPlugin
    {
        private IApplication _application;
        private ActionEventSource _actionEvents;
        private EditorWindow _window;

        public bool Initialize(string pluginFolder)
        {
            // The XAML pack URI is resolved in Renga's AppDomain.
            Assembly.LoadFrom(Path.Combine(pluginFolder, "Renga.WPF.Styles.dll"));
            _application = new Renga.Application();
            var ui = _application.UI;
            var action = ui.CreateAction();
            action.DisplayName = "Library Component Editor";
            action.ToolTip = "Открыть Library Component Editor";
            action.Icon = CreateApplicationIcon(ui);

            var panel = ui.CreateUIPanelExtension();
            panel.AddToolButton(action);
            _actionEvents = new ActionEventSource(action);
            _actionEvents.Triggered += OnOpenEditor;
            try
            {
                ui.AddExtensionToPrimaryPanel(panel);
                return true;
            }
            catch
            {
                Stop();
                throw;
            }
        }

        private static IImage CreateApplicationIcon(IUI ui)
        {
            var icon = ui.CreateImage();
            using (var bitmap = SystemIcons.Application.ToBitmap())
            using (var stream = new MemoryStream())
            {
                bitmap.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
                icon.LoadFromData(stream.ToArray(), Renga.ImageFormat.ImageFormat_PNG);
            }
            return icon;
        }

        private void OnOpenEditor(object sender, EventArgs args)
        {
            try
            {
                OpenEditor(new IntPtr(_application.GetMainWindowHandle()));
            }
            catch (Exception error)
            {
                _application.UI.ShowMessageBox(MessageIcon.MessageIcon_Error,
                    "Library Component Editor", error.GetBaseException().Message);
            }
        }

        private void OpenEditor(IntPtr hostWindow)
        {
            if (_window != null)
            {
                _window.BringToFront();
                return;
            }

            var window = new EditorWindow();
            window.Closed += (sender, args) => _window = null;
            _window = window;
            try
            {
                window.ShowOnHostMonitor(hostWindow);
            }
            catch
            {
                window.Close();
                throw;
            }
        }

        public void Stop()
        {
            if (_actionEvents != null)
            {
                _actionEvents.Triggered -= OnOpenEditor;
                _actionEvents.Dispose();
                _actionEvents = null;
            }
            _window?.Close();
            _application = null;
        }
    }
}
