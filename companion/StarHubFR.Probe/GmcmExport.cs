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
                          List<string> AccessPath, List<string> ClosureStrings);
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
        var closureStrings = new SortedSet<string>(StringComparer.Ordinal);
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
            getter is null ? new List<string>() : AccessPath(getter, 0, closureStrings),
            closureStrings.ToList());
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
    /// <remarks>
    /// Les aides d'intégration courantes enveloppent l'accès réel : celle de
    /// Pathoschild (84 mods du parc, 2 094 options) passe `() => get(GetConfig())`,
    /// où `get` est un délégué capturé. Un champ de la fermeture qui porte un
    /// délégué est donc suivi ; un champ qui porte une `PropertyInfo` ou une
    /// chaîne donne son nom ou sa valeur (clés de dictionnaire, réflexion).
    /// </remarks>
    /// <summary>
    /// Les chaînes capturées par la fermeture du délégué, qu'il les lise ou non.
    /// Content Patcher enregistre chaque option de ses packs avec
    /// `get: _ => field.Value…` : la clé de `config.json` est le paramètre
    /// `name` d'`AddField`, capturé dans la même fermeture pour la description
    /// mais jamais lu par le délégué (≈ 1 400 options du parc, session
    /// v0.4.1). Fermetures imbriquées (`CS$&lt;&gt;8__locals`) suivies d'un niveau.
    /// </summary>
    private static void CollectClosureStrings(object? target, ISet<string> into, int depth)
    {
        if (target is null || depth > 1) return;
        Type type = target.GetType();
        if (!type.Name.Contains("DisplayClass")) return;
        foreach (FieldInfo field in type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
        {
            object? value;
            try { value = field.GetValue(target); } catch { continue; }
            if (value is string text && text.Length is > 0 and <= 200) into.Add(text);
            else if (value is not null && value.GetType().Name.Contains("DisplayClass"))
                CollectClosureStrings(value, into, depth + 1);
        }
    }

    private static List<string> AccessPath(Delegate getter, int depth, ISet<string> closureStrings)
    {
        var path = new List<string>();
        if (depth > 3) return path;
        MethodInfo method = getter.Method;
        object? target = getter.Target;
        try
        {
            // Un délégué lié à une méthode du runtime (`FieldInfo.GetValue`…) :
            // son IL décrit la réflexion, pas le mod — 19 options de BinningSkill
            // en sortaient `[InvocationFlags, DeclaringType, …]` (session v0.4.1).
            if (method.DeclaringType?.Assembly == typeof(object).Assembly)
            {
                if (target is MemberInfo bound) path.Add(bound.Name);
                return path;
            }
            CollectClosureStrings(target, closureStrings, 0);
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
                    i += 4;
                    // Un champ de la fermeture : sa valeur dit plus que son nom.
                    if (member is FieldInfo field && target is not null
                        && field.DeclaringType?.IsAssignableFrom(target.GetType()) == true)
                    {
                        object? captured = null;
                        try { captured = field.GetValue(target); } catch { }
                        switch (captured)
                        {
                            case Delegate inner:
                                path.AddRange(AccessPath(inner, depth + 1, closureStrings));
                                continue;
                            case MemberInfo info:
                                path.Add(info.Name);
                                continue;
                            case string text:
                                path.Add(text);
                                continue;
                        }
                    }
                    string? name = member switch
                    {
                        MethodInfo m when m.Name.StartsWith("get_") => m.Name[4..],
                        FieldInfo f => f.Name,
                        _ => null
                    };
                    if (name is not null && !name.StartsWith("<") && !name.StartsWith("CS$")) path.Add(name);
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
