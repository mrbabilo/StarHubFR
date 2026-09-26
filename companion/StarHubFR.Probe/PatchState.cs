using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using HarmonyLib;

namespace StarHubFR.Probe;

/// <summary>
/// Ce qui a changé dans l'état Harmony depuis le dernier relevé, sans tout
/// relire. `Harmony.GetPatchInfo` désérialise du JSON à chaque appel (Harmony
/// 2.2.2, `PatchInfoSerialization.Deserialize`, options neuves à chaque fois) :
/// ~0,17 ms par méthode, et l'état en compte ~2 800 une fois nos enveloppes
/// posées — 460 ms de parcours et 530 ms de carte chaque matin (session
/// v0.4.9, 20:10), pour rien de neuf.
///
/// L'état partagé est un `Dictionary&lt;MethodBase, byte[]&gt;` que seul
/// `HarmonySharedState.UpdatePatchInfo` écrit, avec un tableau neuf à chaque
/// patch ou retrait : une référence de tableau inchangée veut dire des patches
/// inchangés. Champ interne lu par réflexion ; introuvable (autre version de
/// Harmony), <see cref="Changed"/> rend null et l'appelant relit tout.
///
/// Un relevé par lecteur : la carte et la pose des enveloppes n'avancent pas
/// au même moment (la pose modifie l'état qu'elle vient de lire).
/// </summary>
internal sealed class PatchState
{
    private static readonly Dictionary<MethodBase, byte[]>? State = FindState();

    private Dictionary<MethodBase, byte[]> Seen = new();

    /// <summary>
    /// Méthodes neuves ou dont les patches ont changé depuis <see cref="Commit"/>,
    /// et celles disparues. Null : état illisible, tout relire.
    /// </summary>
    public List<MethodBase>? Changed(out List<MethodBase> removed)
    {
        removed = new List<MethodBase>();
        if (State is null) return null;
        Dictionary<MethodBase, byte[]> now = Copy(State);
        var changed = new List<MethodBase>();
        foreach (var (method, bytes) in now)
        {
            if (!Seen.TryGetValue(method, out byte[]? before) || !ReferenceEquals(before, bytes))
                changed.Add(method);
        }
        removed.AddRange(Seen.Keys.Where(m => !now.ContainsKey(m)));
        return changed;
    }

    /// <summary>L'état actuel devient la référence : à appeler après ses propres patches.</summary>
    public void Commit()
    {
        if (State is not null) Seen = Copy(State);
    }

    private static Dictionary<MethodBase, byte[]> Copy(Dictionary<MethodBase, byte[]> state)
    {
        // Même verrou qu'Harmony autour de ce dictionnaire.
        lock (state) return new Dictionary<MethodBase, byte[]>(state);
    }

    private static Dictionary<MethodBase, byte[]>? FindState()
    {
        try
        {
            Type? type = typeof(Harmony).Assembly.GetType("HarmonyLib.HarmonySharedState");
            FieldInfo? field = type?.GetField("state", BindingFlags.NonPublic | BindingFlags.Static);
            return field?.GetValue(null) as Dictionary<MethodBase, byte[]>;
        }
        catch
        {
            return null;
        }
    }
}
