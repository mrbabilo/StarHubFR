using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using HarmonyLib;
using Microsoft.Xna.Framework.Graphics;
using StardewModdingAPI;
using StardewModdingAPI.Events;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>
/// D4-T6a : la mémoire **retenue** par mod dans les textures résidentes —
/// en plus des allocations par minute de <see cref="ModCosts"/> (qui mesurent
/// la pression sur le GC, pas ce qui reste). Suivi **incrémental, sans
/// patch** : `AssetRequested` retient qui fournit ou édite l'asset
/// (réflexion une fois au démarrage sur les propriétés internal
/// `LoadOperations`/`EditOperations` des arguments — records à champ `Mod`
/// public), `AssetReady` relève la taille (`Width × Height × 4`) via un
/// accès au cache, `AssetsInvalidated` retire — la purge de SMAPI suit.
///
/// Attribution **partielle et assumée** : loader de mod d'abord, éditeur
/// ensuite, sinon `vanilla` — un pack Content Patcher compte pour lui-même
/// (`OnBehalfOf`), plusieurs éditeurs se joignent par `+` ; atlas = une
/// texture, un attributaire ; les textures créées en code (pas d'asset) sont
/// invisibles. RAM gérée, pas
/// VRAM. Le total vit dans `timings.jsonl` (`TexturesMB`, `TextureCount`,
/// `TextureByMod`) à chaque minute, `null` quand `MeasureTextures` est
/// éteint — jamais un zéro muet.
/// </summary>
internal static class TextureMemory
{
    private static IMonitor Monitor = null!;
    private static PropertyInfo? LoadOps, EditOps;
    /// <summary>Clé = `NameWithoutLocale`, valeur = l'attributaire résolu à la
    /// demande **et le type demandé** — le garde : sans lui, le `Load
    /// <Texture2D>` de `OnReady` rejouait la chaîne de chargement des assets
    /// non-texture (traductions = `Dictionary<string,string>`…) et SMAPI
    /// journalisait 1 048 « Mod crashed when loading asset » fausses
    /// (session du 2026-10-05 17:37).</summary>
    private static readonly Dictionary<string, (string Owner, Type DataType)> OwnerPending = new();
    /// <summary>La carte résidente : clé = nom non localisé, valeur = (octets, attributaire).</summary>
    private static readonly Dictionary<string, (long Bytes, string Owner)> Known = new();
    private static bool Armed;
    private static bool Resolving;

    public static bool ArmedNow => Armed;
    public static int Count => Known.Count;

    public static long TotalBytes
    {
        get
        {
            long total = 0;
            foreach (var entry in Known.Values) total += entry.Bytes;
            return total;
        }
    }

    /// <summary>L'octet retenu par attributaire, pour la minute écrite.</summary>
    public static Dictionary<string, long> ByOwner()
    {
        var byOwner = new Dictionary<string, long>();
        foreach (var entry in Known.Values)
        {
            byOwner.TryGetValue(entry.Owner, out long bytes);
            byOwner[entry.Owner] = bytes + entry.Bytes;
        }
        return byOwner;
    }

    public static void Initialize(IModHelper helper, IMonitor monitor, bool enabled)
    {
        Monitor = monitor;
        if (!enabled)
        {
            monitor.Log("Mémoire des textures non relevée : MeasureTextures=false.", LogLevel.Trace);
            return;
        }
        try
        {
            var args = typeof(AssetRequestedEventArgs);
            LoadOps = AccessTools.Property(args, "LoadOperations");
            EditOps = AccessTools.Property(args, "EditOperations");
        }
        catch (Exception ex)
        {
            monitor.Log($"Mémoire des textures : attribution indisponible ({ex.Message}).", LogLevel.Trace);
        }
        helper.Events.Content.AssetRequested += OnRequested;
        helper.Events.Content.AssetReady += OnReady;
        helper.Events.Content.AssetsInvalidated += OnInvalidated;
        Armed = true;
        monitor.Log("Mémoire des textures armée (opt-in MeasureTextures).", LogLevel.Trace);
    }

    /// <summary>L'attributaire se résout **à la demande** : c'est le seul
    /// moment où SMAPI expose qui répond à l'asset. **En dernier**
    /// (`EventPriority.MinValue`) : la sonde se charge en premier
    /// (`ModsToLoadEarly`) — s'exécuter avant Content Patcher, c'est lire ses
    /// `LoadOperations` **avant qu'il les pose** : tout partait `vanilla`
    /// (session du 2026-10-05 17:25, 2 062 textures sans un seul mod).</summary>
    [EventPriority((EventPriority)int.MinValue)]
    private static void OnRequested(object? sender, AssetRequestedEventArgs e)
    {
        if (Resolving) return;
        try
        {
            string id = OwnerOf(e);
            OwnerPending[e.NameWithoutLocale.ToString()] = (id, e.DataType);
        }
        catch (Exception ex)
        {
            Monitor.Log($"Attribution d'asset ratée : {ex.Message}", LogLevel.Trace);
        }
    }

    private static string OwnerOf(AssetRequestedEventArgs e)
    {
        var owners = new List<string>();
        if (LoadOps?.GetValue(e) is IEnumerable<object> loads)
            owners.AddRange(loads.Select(ModIdOf).Where(id => id is not null)!);
        if (owners.Count == 0 && EditOps?.GetValue(e) is IEnumerable<object> edits)
            owners.AddRange(edits.Select(ModIdOf).Where(id => id is not null)!);
        return owners.Count == 0 ? "vanilla" : string.Join("+", owners.Distinct());
    }

    /// <summary>Le pack pour lequel l'opération est faite (`OnBehalfOf`),
    /// sinon le mod qui l'a posée. Content Patcher passe l'identifiant du
    /// pack à `LoadFrom` et à `Edit` (`PatchManager`, CP 2.9.1) : sans ce
    /// champ, les textures de tous ses packs tombaient sous CP seul — 827 Mo
    /// sur 953 dans la session de validation du 2026-10-05.</summary>
    private static string? ModIdOf(object operation)
    {
        var type = operation.GetType();
        return UniqueIdOf(type.GetProperty("OnBehalfOf")?.GetValue(operation))
            ?? UniqueIdOf(type.GetProperty("Mod")?.GetValue(operation));
    }

    private static string? UniqueIdOf(object? metadata)
    {
        // `IModMetadata` n'expose pas d'`Id` : l'identité vit dans
        // `Manifest.UniqueID` (session du 2026-10-05 18:33 : les textures
        // portaient L1/E0 et finissaient vanilla — `GetProperty("Id")` = null
        // sur tous les métadonnées).
        var manifest = metadata?.GetType().GetProperty("Manifest")?.GetValue(metadata);
        return (manifest as StardewModdingAPI.IManifest)?.UniqueID;
    }

    /// <summary>L'objet est en cache **avant** l'événement : `Load` est un
    /// accès, jamais un chargement — et la garde `Resolving` éteint la
    /// récursion si SMAPI relève la chaîne malgré tout.</summary>
    private static void OnReady(object? sender, AssetReadyEventArgs e)
    {
        if (!Armed || Resolving) return;
        Resolving = true;
        try
        {
            string key = e.NameWithoutLocale.ToString();
            if (Known.ContainsKey(key)) return;
            // Le garde du type demandé : ne toucher que les textures — un
            // Load<Texture2D> sur une traduction re-jouait la chaîne et SMAPI
            // journalisait l'échec de cast comme un crash de mod (2026-10-05).
            if (!OwnerPending.TryGetValue(key, out var pending)
                || pending.DataType != typeof(Texture2D)) return;
            object? asset;
            try { asset = Game1.content.Load<Texture2D>(e.Name.ToString()); }
            catch { return; }   // garde en plus : jamais une fausse erreur SMAPI
            if (asset is not Texture2D texture) return;
            long bytes = (long)texture.Width * texture.Height * 4;
            Known[key] = (bytes, pending.Owner);
        }
        catch (Exception ex)
        {
            Monitor.Log($"Relevé de texture raté : {ex.Message}", LogLevel.Trace);
        }
        finally
        {
            Resolving = false;
        }
    }

    private static void OnInvalidated(object? sender, AssetsInvalidatedEventArgs e)
    {
        foreach (var name in e.NamesWithoutLocale)
        {
            string key = name.ToString();
            Known.Remove(key);
            OwnerPending.Remove(key);
        }
    }
}
