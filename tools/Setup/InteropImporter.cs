using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace LibraryComponentEditor.Setup
{
    public sealed class InteropImporter : ITypeLibImporterNotifySink
    {
        private readonly string directory;

        private InteropImporter(string directory) { this.directory = directory; }

        [DllImport("oleaut32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void LoadTypeLibEx(string file, int registration, out ITypeLib library);

        public static void Import(string tlb, string directory)
        {
            ITypeLib library;
            LoadTypeLibEx(tlb, 2 /* REGKIND_NONE */, out library);
            try { new InteropImporter(directory).ResolveRef(library); }
            finally { Marshal.ReleaseComObject(library); }
        }

        public Assembly ResolveRef(object typeLib)
        {
            var name = Marshal.GetTypeLibName((ITypeLib)typeLib);
            var file = "Interop." + name + ".dll";
            var assembly = new TypeLibConverter().ConvertTypeLibToAssembly(typeLib,
                Path.Combine(directory, file), TypeLibImporterFlags.ImportAsX64,
                this, null, null, name, null);
            assembly.Save(file);
            return assembly;
        }

        public void ReportEvent(ImporterEventKind kind, int code, string message)
        {
            if (kind == ImporterEventKind.ERROR_REFTOINVALIDTYPELIB)
                throw new InvalidOperationException(message);
        }
    }
}
