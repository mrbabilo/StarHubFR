using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using HarmonyLib;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// Les options que chaque mod a déclarées à Generic Mod Config Menu, avec
/// leurs **bornes** (min, max, pas) et leurs choix — ce qu'aucun fichier sur
/// disque ne porte : `config.json` n'a que des valeurs, et l'éditeur de
/// StarHubFR n'a pas de curseur faute d'échelle (archive C4, « ne pas porter :
/// le curseur »).
///
/// Lecture seule du registre de GMCM par réflexion
/// (`GenericModConfigMenu.Mod.instance.ConfigManager`, types
/// `NumericModOption`, `ChoiceModOption` — noms relevés dans la source de
/// GMCM, MIT, sans en copier de code). Si GMCM change ces noms, l'export le
/// dit dans le journal et n'écrit rien.
///
/// La clé de `config.json` n'est pas dans GMCM : l'option ne connaît qu'un
/// délégué de lecture (`() => Config.Foo`). On lit son IL pour relever les
/// membres qu'il touche (`AccessPath`), et on joint la valeur courante — l'app
/// rapproche les deux de `config.json`.
/// </summary>
internal static class GmcmExport
{
    private record Option(string Kind, string? FieldId, string? Name, string? Tooltip, string? ValueType,
                          string? Value, string? Min, string? Max, string? Interval, List<string>? Choices,
                          List<string> AccessPath);
    private record ModOptions(string UniqueID, string Name, List<Option> Options);
    private record Export(string CapturedAt, string GmcmVersion, List<ModOptions> Mods);

    public static void Write(IModHelper helper, IMonitor monitor)
    {
        try
        {
            Type? modType = AccessTools.TypeByName("GenericModConfigMenu.Mod");
            object? instance = modType is null ? null : AccessTools.Field(modType, "instance")?.GetValue(null);
            object? manager = instance is null ? null : AccessTools.Field(modType, "ConfigManager")?.GetValue(instance);
            if (manager is null)
            {
                monitor.Log("Options GMCM : registre introuvable (GMCM absent ou structure changée).", LogLevel.Trace);
                return;
            }
            var configs = (IEnumerable)AccessTools.Method(manager.GetType(), "GetAll").Invoke(manager, null)!;
            var mods = new List<ModOptions>();
            int optionCount = 0, bounded = 0;
            foreach (object config in configs)
            {
                var manifest = (IManifest)AccessTools.Property(config.GetType(), "ModManifest").GetValue(config)!;
                var options = new List<Option>();
                var all = (IEnumerable)AccessTools.Method(config.GetType(), "GetAllOptions").Invoke(config, null)!;
                foreach (object option in all)
                {
                    Option? read = Read(option);
                    if (read is null) continue;
                    options.Add(read);
                    optionCount++;
                    if (read.Min is not null || read.Max is not null) bounded++;
                }
                mods.Add(new ModOptions(manifest.UniqueID, manifest.Name, options));
            }
            string gmcmVersion = helper.ModRegistry.Get("spacechase0.GenericModConfigMenu")?.Manifest.Version.ToString() ?? "?";
            var export = new Export(DateTimeOffset.Now.ToString("o"), gmcmVersion, mods);
            string path = Path.Combine(ModEntry.OutputDir, "gmcm-options.json");
            File.WriteAllText(path, JsonSerializer.Serialize(export, new JsonSerializerOptions { WriteIndented = true }));
            monitor.Log($"Options GMCM : {mods.Count} mods, {optionCount} options dont {bounded} bornées → {path}", LogLevel.Info);
        }
        catch (Exception ex)
        {
            monitor.Log($"Options GMCM impossibles à lire : {ex}", LogLevel.Warn);
        }
    }

    private static Option? Read(object option)
    {
        Type t = option.GetType();
        string kind = t.Name.Split('`')[0];
        // Titres, paragraphes, images, liens de page : rien à régler.
        if (kind is "SectionTitleModOption" or "SectionSubHeaderModOption" or "ParagraphModOption"
            or "ImageModOption" or "PageLinkModOption") return null;

        string? Str(object? o) => o switch
        {
            null => null,
            Func<string?> f => Safe(f),
            _ => Convert.ToString(o, System.Globalization.CultureInfo.InvariantCulture)
        };
        object? Prop(string name) => AccessTools.Property(t, name)?.GetValue(option);

        Delegate? getter = AccessTools.Field(t, "GetValue")?.GetValue(option) as Delegate;
        string? value = null;
        try { value = Str(getter?.DynamicInvoke()); } catch { }

        List<string>? choices = null;
        if (Prop("Choices") is IEnumerable list)
            choices = list.Cast<object>().Select(c => Str(c) ?? "").ToList();

        return new Option(
            kind,
            Prop("FieldId") as string,
            Str(Prop("Name")),
            Str(Prop("Tooltip")),
            (Prop("Type") as Type)?.Name,
            value,
            Str(Prop("Minimum")),
            Str(Prop("Maximum")),
            Str(Prop("Interval")),
            choices,
            getter is null ? new List<string>() : AccessPath(getter.Method));
    }

    private static string? Safe(Func<string?> f)
    {
        try { return f(); } catch { return null; }
    }

    /// <summary>
    /// Les membres qu'un délégué de lecture touche, dans l'ordre : pour
    /// `() => this.Config.Section.Foo`, `[Config, Section, Foo]`. Lecture naïve
    /// de l'IL (appels et lectures de champ), suffisante pour ces lambdas de
    /// quelques instructions ; les noms générés par le compilateur sont omis.
    /// </summary>
    private static List<string> AccessPath(MethodInfo method)
    {
        var path = new List<string>();
        try
        {
            byte[]? il = method.GetMethodBody()?.GetILAsByteArray();
            if (il is null) return path;
            Module module = method.Module;
            Type[]? typeArgs = method.DeclaringType?.IsGenericType == true ? method.DeclaringType.GetGenericArguments() : null;
            for (int i = 0; i + 4 < il.Length; i++)
            {
                byte op = il[i];
                // call, callvirt, ldfld, ldsfld : un jeton de 4 octets suit.
                if (op != 0x28 && op != 0x6F && op != 0x7B && op != 0x7E) continue;
                int token = BitConverter.ToInt32(il, i + 1);
                int table = (int)((uint)token >> 24);
                if (table != 0x06 && table != 0x0A && table != 0x04 && table != 0x2B) continue;
                try
                {
                    MemberInfo? member = module.ResolveMember(token, typeArgs, null);
                    string? name = member switch
                    {
                        MethodInfo m when m.Name.StartsWith("get_") => m.Name[4..],
                        FieldInfo f => f.Name,
                        _ => null
                    };
                    if (name is not null && !name.StartsWith("<")) path.Add(name);
                    i += 4;
                }
                catch
                {
                    // Octet de donnée pris pour un opcode : on continue.
                }
            }
        }
        catch
        {
        }
        return path;
    }
}
