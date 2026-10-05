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
/// ensuite, sinon `vanilla` ; atlas = une texture, un attributaire ; les
/// textures créées en code (pas d'asset) sont invisibles. RAM gérée, pas
/// VRAM. Le total vit dans `timings.jsonl` (`TexturesMB`, `TextureCount`,
/// `TextureByMod`) à chaque minute, `null` quand `MeasureTextures` est
/// éteint — jamais un zéro muet.
/// </summary>
internal static class TextureMemory
{
    private static IMonitor Monitor = null!;
    private static PropertyInfo? LoadOps, EditOps;
    /// <summary>Clé = `NameWithoutLocale`, valeur = l'attributaire résolu à la demande.</summary>
    private static readonly Dictionary<string, string> OwnerPending = new();
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
    /// moment où SMAPI expose qui répond à l'asset.</summary>
    private static void OnRequested(object? sender, AssetRequestedEventArgs e)
    {
        if (Resolving) return;
        try
        {
            string id = OwnerOf(e);
            OwnerPending[e.NameWithoutLocale.ToString()] = id;
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

    private static string? ModIdOf(object operation)
    {
        var mod = operation.GetType().GetProperty("Mod")?.GetValue(operation);
        return mod?.GetType().GetProperty("Id")?.GetValue(mod) as string;
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
            object? asset;
            try { asset = Game1.content.Load<Texture2D>(e.Name.ToString()); }
            catch { return; }   // pas une texture (map, donnée…) : ignoré
            if (asset is not Texture2D texture) return;
            long bytes = (long)texture.Width * texture.Height * 4;
            OwnerPending.TryGetValue(key, out string? owner);
            Known[key] = (bytes, owner ?? "vanilla");
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
