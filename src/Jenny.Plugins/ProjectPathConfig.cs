using System.IO;
using System.Collections.Generic;
using DesperateDevs.Serialization;

namespace Jenny.Plugins
{
    public class ProjectPathConfig : AbstractConfigurableConfig
    {
        readonly string _projectPathKey = $"{typeof(ProjectPathConfig).Namespace}.ProjectPath";

        public override Dictionary<string, string> DefaultProperties => new Dictionary<string, string>
        {
            {_projectPathKey, "Assembly-CSharp.csproj"}
        };

        public string ProjectPath => _preferences[_projectPathKey];
        public string ProjectRoot => Path.GetDirectoryName(ProjectPath);
    }
}
