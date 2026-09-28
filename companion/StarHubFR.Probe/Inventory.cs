using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>
/// D4-T4 — l'inventaire d'une session : les mods chargés par SMAPI, leur
/// version et l'empreinte de leur `config.json`, puis chaque réglage changé
/// en cours de partie. L'app coupe les sessions en segments d'inventaire
/// constant pour comparer « avant » et « après ». La sonde constate, ne
/// compare jamais.
///
/// Fichiers : `inventory.jsonl` (une ligne par événement) et
/// `configs/&lt;sha256&gt;.json` (le contenu d'un `config.json`, écrit une seule
/// fois par empreinte : l'app en tire le diff clé par clé).
///
/// Tout le travail disque tourne en tâche de fond, un relevé à la fois : rien
/// sur le fil du jeu.
/// </summary>
internal static class Inventory
{
    private sealed class Watched
    {
        public readonly string Id;
        public readonly string Path;
        public DateTime? Stamp;
        public string? Sha;

        // Pas de `required` : net6.0 n'a pas `RequiredMemberAttribute`.
        public Watched(string id, string path, DateTime? stamp, string? sha)
        {
            Id = id;
            Path = path;
            Stamp = stamp;
            Sha = sha;
        }
    }

    private static readonly List<Watched> WatchedConfigs = new();
    private static readonly object FileLock = new();
    /// <summary>
    /// Un seul travail à la fois sur `WatchedConfigs`. Le lancement **attend**
    /// son tour (sa ligne ne doit jamais manquer) ; le relevé de la minute
    /// **passe** son tour si un autre tourne encore.
    /// </summary>
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static IMonitor? Monitor;
    /// <summary>
    /// Début du relevé précédent (UTC) : borne basse de `ChangedAt`. Un
    /// changement vu maintenant a eu lieu après que ce relevé a lu les dates.
    /// </summary>
    private static DateTime LastScanUtc;

    private static string InventoryPath => Path.Combine(ModEntry.OutputDir, "inventory.jsonl");
    private static string ContentDir => Path.Combine(ModEntry.OutputDir, "configs");

    /// <summary>
    /// Au `GameLaunched` : la liste des mods est prise ici (registre de SMAPI,
    /// fil du jeu), les lectures et les hachages partent en tâche de fond.
    /// </summary>
    public static void WriteLaunch(IModHelper helper, IMonitor monitor, string probeVersion)
    {
        Monitor = monitor;
        var mods = helper.ModRegistry.GetAll()
            .OrderBy(info => info.Manifest.UniqueID, StringComparer.OrdinalIgnoreCase)
            .Select(info => (Id: info.Manifest.UniqueID, Version: info.Manifest.Version.ToString(),
                             Directory: ModDirectory.Of(info)))
            .ToList();
        string smapi = Constants.ApiVersion.ToString();
        string game = Game1.version;
        string session = FrameTimings.Session;
        Task.Run(() =>
        {
            Gate.Wait();
            try
            {
                LastScanUtc = DateTime.UtcNow;
                RemoveOrphanTemps();
                var lines = new List<object>();
                foreach (var mod in mods)
                {
                    string? path = mod.Directory is null ? null : Path.Combine(mod.Directory, "config.json");
                    Observation seen = path is null ? new Observation(ReadKind.Absent) : Observe(path);
                    string? sha = seen.Kind == ReadKind.Present ? seen.Sha : null;
                    if (path is not null)
                        WatchedConfigs.Add(new Watched(mod.Id, path, seen.Kind == ReadKind.Present ? seen.Stamp : null, sha));
                    lines.Add(new { mod.Id, mod.Version, Config = sha });
                }
                Append(new { Session = session, At = Now(), Kind = "launch", Probe = probeVersion,
                             Smapi = smapi, Game = game, Mods = lines });
                Log($"Inventaire : {lines.Count} mods, {WatchedConfigs.Count(w => w.Sha is not null)} config.json.");
            }
            catch (Exception ex)
            {
                Log($"Inventaire du lancement abandonné : {ex}");
            }
            finally
            {
                Gate.Release();
            }
        });
    }

    /// <summary>
    /// Un relevé coupé par la fermeture du jeu laisse un `.tmp-` : jamais un
    /// nom d'empreinte (renommage atomique), mais du déchet, enlevé ici.
    /// </summary>
    private static void RemoveOrphanTemps()
    {
        try
        {
            if (!Directory.Exists(ContentDir)) return;
            foreach (string temp in Directory.EnumerateFiles(ContentDir, "*.tmp-*"))
                File.Delete(temp);
        }
        catch (Exception ex)
        {
            // Du déchet qui reste : jamais une raison de perdre la ligne `launch`.
            Log($"Inventaire : temporaires non enlevés ({ex.Message}).");
        }
    }

    /// <summary>
    /// À chaque minute écrite : les dates de modification d'abord (lecture de
    /// métadonnées), le hachage seulement pour ce qui a bougé.
    /// </summary>
    public static void CheckNow()
    {
        // `WatchedConfigs` n'est lu et écrit que sous `Gate`, dans la tâche de
        // fond : la liste peut être en train de se remplir (lancement).
        if (!Gate.Wait(0)) return;
        string session = FrameTimings.Session;
        Task.Run(() =>
        {
            try
            {
                if (WatchedConfigs.Count == 0) return;
                DateTime notBefore = LastScanUtc;
                LastScanUtc = DateTime.UtcNow;
                var changed = new Dictionary<string, string?>();
                DateTime? latest = null;
                foreach (var watched in WatchedConfigs)
                {
                    Observation seen;
                    try
                    {
                        DateTime? stamp = File.Exists(watched.Path) ? File.GetLastWriteTimeUtc(watched.Path) : null;
                        if (stamp == watched.Stamp) continue;
                        seen = Observe(watched.Path);
                    }
                    catch (Exception ex)
                    {
                        // Un mod qui lève ne prive pas les suivants de leur relevé.
                        Log($"Inventaire : {watched.Path} non relevé ({ex.Message}).");
                        seen = new Observation(ReadKind.Error);
                    }
                    if (!InventoryRules.Apply(ref watched.Stamp, ref watched.Sha, seen)) continue;
                    changed[watched.Id] = watched.Sha;
                    if (seen.Stamp is { } s && (latest is null || s > latest)) latest = s;
                }
                if (changed.Count == 0) return;
                // `ChangedAt` : quand le fichier a changé, pas quand on l'a vu.
                // C'est lui qui coupe la session côté app — la minute du
                // changement, pas celle du relevé.
                DateTime changedAt = InventoryRules.ChangedAt(latest, notBefore, DateTime.UtcNow);
                Append(new { Session = session, At = Now(),
                             ChangedAt = new DateTimeOffset(changedAt, TimeSpan.Zero).ToLocalTime().ToString("o"),
                             Kind = "configChanged", Configs = changed });
                Log($"Inventaire : réglage changé ({string.Join(", ", changed.Keys)}).");
            }
            catch (Exception ex)
            {
                Log($"Inventaire : relevé de la minute abandonné ({ex.Message}).");
            }
            finally
            {
                Gate.Release();
            }
        });
    }

    /// <summary>
    /// Ce qu'on voit d'un `config.json`, contenu rangé au passage. Absent : la
    /// date du dossier, quand la suppression a eu lieu. Illisible : une erreur,
    /// jamais une absence — la minute suivante réessaiera.
    /// </summary>
    private static Observation Observe(string path)
    {
        byte[] bytes;
        DateTime stamp;
        try
        {
            if (!File.Exists(path))
            {
                string? dir = Path.GetDirectoryName(path);
                return new Observation(ReadKind.Absent,
                    dir is not null && Directory.Exists(dir) ? Directory.GetLastWriteTimeUtc(dir) : null);
            }
            stamp = File.GetLastWriteTimeUtc(path);
            bytes = File.ReadAllBytes(path);
        }
        catch (Exception ex)
        {
            Log($"Inventaire : {path} illisible ({ex.Message}).");
            return new Observation(ReadKind.Error);
        }
        string sha = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        try
        {
            StoreContent(sha, bytes);
        }
        catch (Exception ex)
        {
            // Le réglage a bien été lu : son empreinte vaut, seul le contenu
            // manque (le contrôleur le signale). Ne pas l'effacer pour ça.
            Log($"Inventaire : contenu de {path} non rangé ({ex.Message}).");
        }
        return new Observation(ReadKind.Present, stamp, sha);
    }

    /// <summary>
    /// Une fois par empreinte, jamais réécrit. Écrit sous un nom temporaire puis
    /// renommé : un contenu tronqué (jeu fermé en pleine écriture) ne porte
    /// jamais un nom d'empreinte.
    /// </summary>
    private static void StoreContent(string sha, byte[] bytes)
    {
        string target = Path.Combine(ContentDir, sha + ".json");
        if (File.Exists(target)) return;
        Directory.CreateDirectory(ContentDir);
        string temp = target + ".tmp-" + Guid.NewGuid().ToString("N");
        File.WriteAllBytes(temp, bytes);
        try
        {
            File.Move(temp, target);
        }
        catch (IOException)
        {
            // Déjà écrit entre-temps (même empreinte) : le nôtre est de trop.
            File.Delete(temp);
        }
    }

    private static void Append(object line)
    {
        try
        {
            lock (FileLock)
                File.AppendAllText(InventoryPath, JsonSerializer.Serialize(line) + "\n");
        }
        catch (Exception ex)
        {
            Log($"Inventaire non écrit : {ex.Message}");
        }
    }

    private static string Now() => DateTimeOffset.Now.ToString("o");

    private static void Log(string message)
    {
        try { Monitor?.Log(message, LogLevel.Trace); }
        catch (ObjectDisposedException) { }   // journal de SMAPI déjà fermé (ProcessExit)
    }
}
