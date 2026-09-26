using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Threading;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// Coupe-circuit de l'enveloppe des patches (D4-T5). Session v0.4.5, option
/// active : ~30 Go déversés dans le terminal de SMAPI, disque plein, aucun
/// journal écrit, cause inconnue. Une enveloppe fausse lève à chaque appel du
/// patch — des milliers de fois par trame — et chaque levée est journalisée
/// par SMAPI ou par le mod qui l'attrape.
///
/// Le disjoncteur écoute les exceptions de première chance de tout le
/// processus et déclenche sur :
/// - la première `InvalidProgramException` : IL refusé par le JIT, jamais
///   légitime dans un jeu qui tournait sans l'enveloppe ;
/// - la 100ᵉ exception levée **dans** une méthode enveloppée (son nom porte
///   <see cref="PatchCosts.WrapperId"/>) ;
/// - plus de 8 millions de caractères vers le terminal en 10 secondes
///   (<see cref="ConsoleVolume"/>), quelle qu'en soit la cause — le symptôme de
///   la v0.4.5. La v0.4.6 comptait 1 000 exceptions par seconde : elle a sauté
///   à tort au chargement, sur les `ArgumentException` que MonoMod lève et
///   rattrape lui-même en posant des patches (« Type must derive from
///   Delegate », `GetMethodHandle`) ; une exception rattrapée n'écrit rien ;
/// - une mesure interrompue (<see cref="ModCosts.Interrupted"/>) : les
///   enveloppes coûtent alors sans plus rien mesurer ;
/// - l'échéance : 5 minutes après le chargement de la sauvegarde, 15 après
///   l'armement au plus tard. Seul ce déclencheur borne ce que les autres ne
///   voient pas : le journal SMAPI de la session v0.4.5 n'a pas été écrit, le
///   déversement ne passait donc peut-être pas par des exceptions.
///
/// Il retire alors toutes les enveloppes au tick suivant, sur le fil du jeu,
/// écrit la cause, l'étape et l'exception **du déclencheur qui a sauté** dans
/// `disjoncteur.txt`, et le dit une fois.
/// Un déclenchement à tort ne coûte que la mesure des patches.
/// </summary>
internal static class PatchBreaker
{
    private const int WrappedExceptionLimit = 100;
    private const long ConsoleLimit = 8_000_000;
    private static readonly TimeSpan ConsoleWindow = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan AfterSaveLoaded = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan AfterArming = TimeSpan.FromMinutes(15);

    private static IMonitor Monitor = null!;
    private static int WrappedExceptions;
    private static readonly Stopwatch SinceWindow = new();
    private static long WindowStartChars;
    private static Exception? FirstSeen;
    /// <summary>La preuve du déclencheur qui a sauté, pas d'un autre.</summary>
    private static Exception? Evidence;
    private static string? Reason;
    private static readonly Stopwatch SinceArming = new();
    private static readonly Stopwatch SinceStage = new();
    private static readonly Stopwatch SinceSaveLoaded = new();
    private static string Stage = "";
    private static int Handled;
    private static bool Armed;

    /// <summary>Évite qu'une exception levée par le gestionnaire ne le rappelle.</summary>
    [ThreadStatic] private static bool InHandler;

    public static void Arm(IMonitor monitor)
    {
        if (Armed) return;
        Armed = true;
        Monitor = monitor;
        SinceArming.Start();
        ConsoleVolume.Install();
        WindowStartChars = ConsoleVolume.Written;
        SinceWindow.Start();
        AppDomain.CurrentDomain.FirstChanceException += OnException;
    }

    /// <summary>Tout fil, chaque exception du processus : rien d'alloué hors déclenchement.</summary>
    private static void OnException(object? sender, FirstChanceExceptionEventArgs e)
    {
        if (InHandler || Volatile.Read(ref Reason) is not null) return;
        InHandler = true;
        try
        {
            Exception ex = e.Exception;
            if (ex is InvalidProgramException)
            {
                Trip($"IL refusé par le JIT : {ex.Message}", ex);
                return;
            }

            // Le nom de la méthode de remplacement porte l'identifiant de
            // l'enveloppe (`UpdatePostfix_PatchedBy<…PatchCosts>`). La pile
            // en repli : une méthode dynamique peut rendre un TargetSite nul.
            string? site = ex.TargetSite?.Name ?? ex.StackTrace;
            if (site is null || !site.Contains(PatchCosts.WrapperId, StringComparison.Ordinal)) return;
            Interlocked.CompareExchange(ref FirstSeen, ex, null);
            if (Interlocked.Increment(ref WrappedExceptions) >= WrappedExceptionLimit)
                Trip($"{WrappedExceptionLimit} exceptions levées dans des patches enveloppés", FirstSeen);
        }
        catch
        {
            // Rien ne sort d'ici : le gestionnaire voit les exceptions des autres.
        }
        finally
        {
            InHandler = false;
        }
    }

    private static void Trip(string reason, Exception? evidence)
    {
        if (Interlocked.CompareExchange(ref Reason, reason, null) is null)
            Volatile.Write(ref Evidence, evidence);
    }

    /// <summary>
    /// Étape atteinte (GameLaunched, SaveLoaded…) : écrite avec la cause, un
    /// déclenchement à tort pendant un chargement se lit alors comme tel.
    /// </summary>
    public static void StageReached(string stage)
    {
        Stage = stage;
        SinceStage.Restart();
        // La première seulement : DayStarted suit, un retour au titre puis un
        // autre chargement ne repoussent pas l'échéance.
        if (stage == "SaveLoaded" && !SinceSaveLoaded.IsRunning) SinceSaveLoaded.Start();
    }

    /// <summary>Fil du jeu, à chaque tick : retire les enveloppes si le disjoncteur a sauté.</summary>
    public static void Poll()
    {
        if (!Armed) return;
        if (ModCosts.Interrupted && Volatile.Read(ref Reason) is null)
            Trip($"mesure interrompue ({ModCosts.InterruptReason})", null);
        if (SinceSaveLoaded.Elapsed >= AfterSaveLoaded || SinceArming.Elapsed >= AfterArming)
            Trip("échéance de la mesure atteinte", null);
        long written = ConsoleVolume.Written - WindowStartChars;
        if (written > ConsoleLimit)
            Trip($"{written / 1_000_000} millions de caractères vers le terminal en moins de {ConsoleWindow.TotalSeconds:0} s", null);
        if (SinceWindow.Elapsed >= ConsoleWindow)
        {
            WindowStartChars = ConsoleVolume.Written;
            SinceWindow.Restart();
        }
        string? reason = Volatile.Read(ref Reason);
        if (reason is null || Interlocked.Exchange(ref Handled, 1) == 1) return;

        AppDomain.CurrentDomain.FirstChanceException -= OnException;
        var watch = Stopwatch.StartNew();
        string outcome = PatchCosts.Disarm(reason);
        watch.Stop();
        try
        {
            File.WriteAllText(Path.Combine(ModEntry.OutputDir, "disjoncteur.txt"),
                $"Cause : {reason}\n{outcome} ({watch.ElapsedMilliseconds} ms)\n"
                + $"Étape : {Stage}, depuis {SinceStage.Elapsed.TotalSeconds:0} s ; armé depuis {SinceArming.Elapsed.TotalSeconds:0} s\n\n"
                + $"Dernière ligne vers le terminal :\n{Excerpt(ConsoleVolume.Last)}\n\n"
                + $"Exception du déclencheur :\n{Volatile.Read(ref Evidence)?.ToString() ?? "(aucune)"}\n");
        }
        catch
        {
            // Disque plein possible : le message ci-dessous suffit.
        }
        Monitor.Log($"Coût des patches coupé : {reason}. {outcome}. Détail : disjoncteur.txt", LogLevel.Warn);
    }

    private static string Excerpt(string? line) =>
        line is null ? "(aucune)" : line.Length <= 2_000 ? line : line[..2_000] + "…";
}
