using System;
using System.Collections.Generic;
using System.IO;
using DesperateDevs.Serialization;

namespace Jenny.Plugins
{
    public class TargetDirectoryConfig : AbstractConfigurableConfig
    {
        readonly string _targetDirectoryKey = $"{typeof(TargetDirectoryConfig).Namespace}.TargetDirectory";

        public override Dictionary<string, string> DefaultProperties => new Dictionary<string, string>
        {
            {_targetDirectoryKey, "Assets"}
        };

        public string TargetDirectory => _preferences[_targetDirectoryKey].ToSafeDirectory();

        public string GetPathRelativeTo(ProjectPathConfig projectPath)
        {
            if (projectPath.ProjectRoot.Length == 0)
            {
                return TargetDirectory;
            }

            if (!TargetDirectory.StartsWith(projectPath.ProjectRoot))
            {
                throw new Exception(
                        $"Path {_targetDirectoryKey}: {TargetDirectory} is outside of the csproj direcotry: {projectPath.ProjectPath}. \n" +
                        $"Did you mean: {projectPath.ProjectRoot + Path.DirectorySeparatorChar + TargetDirectory}?");
            }

            return TargetDirectory[(projectPath.ProjectRoot.Length + 1)..];
        }
    }

    public static class TargetDirectoryStringExtension
    {
        public static string ToSafeDirectory(this string directory)
        {
            if (string.IsNullOrEmpty(directory) || directory == ".")
                return "Generated";

            if (directory.EndsWith("/", StringComparison.Ordinal))
                directory = directory.Substring(0, directory.Length - 1);

            if (!directory.EndsWith("/Generated", StringComparison.OrdinalIgnoreCase))
                directory += "/Generated";

            return directory;
        }
    }
}
