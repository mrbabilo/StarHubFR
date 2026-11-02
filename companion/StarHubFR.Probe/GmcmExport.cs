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
                          List<string>? ChoiceLabels, List<string> AccessPath, List<string> ClosureStrings,
                          string? Section);
    private record ModOptions(string UniqueID, string Name, string Version, string? ConfigSnapshot, List<Option> Options);
    private record Export(string CapturedAt, string GmcmVersion, string Language, List<ModOptions> Mods);

    /// <summary>Ce que la session a déjà exporté : la règle <see cref="GmcmExportRule"/> compare.</summary>
    private static int? ExportedMods;
    private static string? ExportedLanguage;

    public static void Write(IModHelper helper, IMonitor monitor, bool force = false)
    {
        try
        {
            int registryMods = helper.ModRegistry.GetAll().Count();
            string language = StardewValley.LocalizedContentManager.CurrentLanguageCode.ToString();
            if (!GmcmExportRule.ShouldWrite(ExportedMods, ExportedLanguage, registryMods, language, force))
            {
                monitor.Log($"Options GMCM : déjà exportées cette session ({registryMods} mods, {language}), réécriture sautée.", LogLevel.Trace);
                return;
            }
            Type? modType = AccessTools.TypeByName("GenericModConfigMenu.Mod");
            object? instance = modType is null ? null : AccessTools.Field(modType, "instance")?.GetValue(null);
            object? manager = instance is null ? null : AccessTools.Field(modType, "ConfigManager")?.GetValue(instance);
            var configs = manager is null ? Array.Empty<object>()
                : (IEnumerable)AccessTools.Method(manager.GetType(), "GetAll").Invoke(manager, null)!;
            var mods = new List<ModOptions>();
            int optionCount = 0, bounded = 0;
            foreach (object config in configs)
            {
                var manifest = (IManifest)AccessTools.Property(config.GetType(), "ModManifest").GetValue(config)!;
                var options = new List<Option>();
                var all = (IEnumerable)AccessTools.Method(config.GetType(), "GetAllOptions").Invoke(config, null)!;
                // Les options suivent leur titre de section dans le menu :
                // l'éditeur de l'app les range sous le même titre.
                string? section = null;
                foreach (object option in all)
                {
                    if (option.GetType().Name == "SectionTitleModOption")
                    {
                        section = AccessTools.Property(option.GetType(), "Name")?.GetValue(option) is Func<string> title
                            ? Safe(title) : null;
                        continue;
                    }
                    Option? read = Read(option, section);
                    if (read is null) continue;
                    options.Add(read);
                    optionCount++;
                    if (read.Min is not null || read.Max is not null) bounded++;
                }
                mods.Add(new ModOptions(manifest.UniqueID, manifest.Name, manifest.Version.ToString(),
                                        ConfigSnapshot(helper, manifest.UniqueID, monitor), options));
            }
            // Un mod qui trouve MCM s'y inscrit au lieu de GMCM ; MCM reprend
            // aussi les inscriptions GMCM, déjà lues ci-dessus.
            var known = new HashSet<string>(mods.Select(m => m.UniqueID), StringComparer.OrdinalIgnoreCase);
            foreach (var (manifest, options) in McmOptions())
            {
                if (!known.Add(manifest.UniqueID)) continue;
                optionCount += options.Count;
                bounded += options.Count(o => o.Min is not null || o.Max is not null);
                mods.Add(new ModOptions(manifest.UniqueID, manifest.Name, manifest.Version.ToString(),
                                        ConfigSnapshot(helper, manifest.UniqueID, monitor), options));
            }
            if (mods.Count == 0)
            {
                monitor.Log("Options GMCM : aucun registre lisible (GMCM et MCM absents ou structure changée).", LogLevel.Trace);
                return;
            }
            string gmcmVersion = helper.ModRegistry.Get("spacechase0.GenericModConfigMenu")?.Manifest.Version.ToString() ?? "?";
            var export = new Export(DateTimeOffset.Now.ToString("o"), gmcmVersion, language, mods);
            string path = Path.Combine(ModEntry.OutputDir, "gmcm-options.json");
            File.WriteAllText(path, JsonSerializer.Serialize(export, new JsonSerializerOptions { WriteIndented = true }));
            ExportedMods = registryMods;
            ExportedLanguage = language;
            monitor.Log($"Options GMCM : {mods.Count} mods, {optionCount} options dont {bounded} bornées → {path}", LogLevel.Info);
        }
        catch (Exception ex)
        {
            monitor.Log($"Options GMCM impossibles à lire : {ex}", LogLevel.Warn);
        }
    }

    /// <summary>
    /// Le `config.json` du mod tel qu'il est à l'instant de la capture. L'app y
    /// vérifie que chaque option GMCM lit bien la clé qu'elle lui attribue
    /// (valeur égale), sans dépendre des éditions faites depuis (D4-T7).
    /// </summary>
    private static string? ConfigSnapshot(IModHelper helper, string uniqueId, IMonitor monitor)
    {
        try
        {
            string? directory = ModDirectory.Of(helper.ModRegistry.Get(uniqueId));
            if (directory is null)
            {
                monitor.Log($"Options GMCM : dossier de {uniqueId} introuvable, pas de copie de config.json.", LogLevel.Trace);
                return null;
            }
            string path = Path.Combine(directory, "config.json");
            return File.Exists(path) ? File.ReadAllText(path) : null;
        }
        catch (Exception ex)
        {
            monitor.Log($"Options GMCM : config.json de {uniqueId} illisible ({ex.Message}).", LogLevel.Trace);
            return null;
        }
    }

    private static Option? Read(object option, string? section)
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

        // Le texte que GMCM montre pour chaque valeur (`FormatChoice`, GMCM
        // 1.16.0) : `both` s'affiche « Both ». Même ordre que `Choices`.
        List<string>? choiceLabels = null;
        if (choices is not null && Prop("FormatChoice") is Func<string, string> format)
        {
            choiceLabels = choices.Select(choice =>
            {
                try { return format(choice) ?? choice; }
                catch { return choice; }
            }).ToList();
        }

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
            choiceLabels,
            getter is null ? new List<string>() : AccessPath(getter, 0, closureStrings),
            closureStrings.ToList(),
            section);
    }

    /// <summary>
    /// Le registre de ModernConfigMenu (MCM 2.3.4 : `ModEntry.Instance`,
    /// champ privé `Registry`, `All` → `RegisteredMod.Manifest` et `Settings`),
    /// lu par réflexion et en lecture seule, comme celui de GMCM. Noms relevés
    /// en décompilant MCM 2.3.4 (2026-11-02), sans en copier de code. Structure
    /// changée : vide, l'export GMCM reste.
    /// </summary>
    private static List<(IManifest Manifest, List<Option> Options)> McmOptions()
    {
        var found = new List<(IManifest, List<Option>)>();
        try
        {
            Type? entry = AccessTools.TypeByName("ModernConfigMenu.ModEntry");
            object? instance = entry is null ? null : AccessTools.Property(entry, "Instance")?.GetValue(null);
            object? registry = instance is null ? null : AccessTools.Field(entry, "Registry")?.GetValue(instance);
            if (registry is null || AccessTools.Property(registry.GetType(), "All")?.GetValue(registry) is not IEnumerable all)
                return found;
            foreach (object mod in all)
            {
                object? Of(string name) => AccessTools.Property(mod.GetType(), name)?.GetValue(mod);
                if (Of("Manifest") is not IManifest manifest || Of("Settings") is not IEnumerable settings) continue;
                var options = settings.Cast<object>().Select(ReadMcm).OfType<Option>().ToList();
                if (options.Count > 0) found.Add((manifest, options));
            }
        }
        catch
        {
            // Une version de MCM qui a changé de forme : rien de plus que GMCM.
        }
        return found;
    }

    private static Option? ReadMcm(object setting)
    {
        Type t = setting.GetType();
        string? kind = GmcmExportRule.McmKind(t.Name);
        if (kind is null) return null;
        object? Prop(string name) => AccessTools.Property(t, name)?.GetValue(setting);
        string? Str(object? o) => o is null ? null : Convert.ToString(o, System.Globalization.CultureInfo.InvariantCulture);

        Delegate? getter = (Prop("Get") ?? Prop("GetKeybindList")) as Delegate;
        var closureStrings = new SortedSet<string>(StringComparer.Ordinal);
        string? value = null;
        try { value = Str(getter?.DynamicInvoke()); } catch { }

        List<string>? choices = (Prop("Choices") as string[])?.ToList();
        List<string>? choiceLabels = null;
        if (choices is not null && Prop("Format") is Func<string, string> format)
        {
            choiceLabels = choices.Select(choice =>
            {
                try { return format(choice) ?? choice; }
                catch { return choice; }
            }).ToList();
        }
        string? tooltip = null, section = null;
        try { tooltip = Prop("Tooltip") as string; section = Prop("Section") as string; } catch { }

        return new Option(
            kind,
            null,
            Prop("NameGetter") is Func<string> name ? Safe(name) : null,
            tooltip,
            getter?.Method.ReturnType.Name,
            value,
            Str(Prop("Min")),
            Str(Prop("Max")),
            Str(Prop("Interval")),
            choices,
            choiceLabels,
            getter is null ? new List<string>() : AccessPath(getter, 0, closureStrings),
            closureStrings.ToList(),
            section);
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
    /// Les chaînes capturées par la fermeture vont dans
    /// <paramref name="closureStrings"/>, qu'elles soient lues ou non :
    /// Content Patcher enregistre chaque option de ses packs avec
    /// `get: _ => field.Value…`, la clé de `config.json` est le paramètre
    /// `name` d'`AddField`, capturé dans la même fermeture pour la description
    /// mais jamais lu par le délégué (≈ 1 400 options du parc, session v0.4.1).
    /// </summary>
    /// <remarks>
    /// Les aides d'intégration courantes enveloppent l'accès réel : celle de
    /// Pathoschild (84 mods du parc, 2 094 options) passe `() => get(GetConfig())`,
    /// où `get` est un délégué capturé. Un champ de la fermeture qui porte un
    /// délégué est donc suivi ; un champ qui porte une `PropertyInfo` ou une
    /// chaîne donne son nom ou sa valeur (clés de dictionnaire, réflexion).
    /// Fermetures imbriquées (`CS$&lt;&gt;8__locals`) suivies d'un niveau.
    /// </remarks>
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
