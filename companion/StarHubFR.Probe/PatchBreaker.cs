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
/// Les trois premiers sont des **urgences** : toutes les enveloppes sont
/// retirées au tick suivant, sur le fil du jeu. Les deux derniers ne sont
/// dangereux pour rien : la mesure s'arrête (enveloppes en veille,
/// <see cref="PatchCosts.Pause"/>) et le retrait attend la fin de la journée ou
/// le retour au titre (<see cref="CalmMoment"/>) — retirer 1 700 enveloppes a
/// figé le jeu 4,1 s en pleine partie (session v0.4.7). Une urgence survenue
/// pendant la veille retire tout aussitôt.
///
/// Cause, étape et exception **du déclencheur qui a sauté** vont dans
/// `disjoncteur.txt`, et une ligne au journal. Un déclenchement à tort ne coûte
/// que la mesure des patches.
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
    /// <summary>Cause urgente, posée depuis n'importe quel fil.</summary>
    private static string? Urgent;
    /// <summary>Cause sans danger, fil du jeu seulement.</summary>
    private static string? Calm;
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
        if (InHandler || Volatile.Read(ref Urgent) is not null) return;
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
        if (Interlocked.CompareExchange(ref Urgent, reason, null) is null)
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

    /// <summary>Fil du jeu, à chaque tick, entre deux ticks : aucun patch enveloppé n'y est ouvert.</summary>
    public static void Poll()
    {
        if (!Armed || Handled != 0) return;
        if (Calm is null)
        {
            if (ModCosts.Interrupted)
                Calm = $"mesure interrompue ({ModCosts.InterruptReason})";
            else if (SinceSaveLoaded.Elapsed >= AfterSaveLoaded || SinceArming.Elapsed >= AfterArming)
                Calm = "échéance de la mesure atteinte";
            if (Calm is not null)
            {
                PatchCosts.Pause(Calm);
                const string outcome = "mesure arrêtée, enveloppes en veille jusqu'à la fin de la journée ou au retour au titre";
                WriteFile(Calm, outcome, null);
                Monitor.Log($"Coût des patches : {Calm}, {outcome}.", LogLevel.Info);
            }
        }

        long written = ConsoleVolume.Written - WindowStartChars;
        if (written > ConsoleLimit)
            Trip($"{written / 1_000_000} millions de caractères vers le terminal en moins de {ConsoleWindow.TotalSeconds:0} s", null);
        if (SinceWindow.Elapsed >= ConsoleWindow)
        {
            WindowStartChars = ConsoleVolume.Written;
            SinceWindow.Restart();
        }

        string? urgent = Volatile.Read(ref Urgent);
        if (urgent is not null) Finish(urgent, LogLevel.Warn);
    }

    /// <summary>Fin de journée, retour au titre : un gel ne s'y voit pas.</summary>
    public static void CalmMoment()
    {
        if (Armed && Handled == 0 && Calm is not null) Finish(Calm, LogLevel.Info);
    }

    private static void Finish(string reason, LogLevel level)
    {
        if (Interlocked.Exchange(ref Handled, 1) == 1) return;
        AppDomain.CurrentDomain.FirstChanceException -= OnException;
        var watch = Stopwatch.StartNew();
        string outcome = PatchCosts.Disarm(reason);
        watch.Stop();
        WriteFile(reason, $"{outcome} ({watch.ElapsedMilliseconds} ms)", Volatile.Read(ref Evidence));
        Monitor.Log($"Coût des patches coupé : {reason}. {outcome}. Détail : disjoncteur.txt", level);
    }

    private static void WriteFile(string reason, string outcome, Exception? evidence)
    {
        try
        {
            File.WriteAllText(Path.Combine(ModEntry.OutputDir, "disjoncteur.txt"),
                $"Cause : {reason}\n{outcome}\n"
                + $"Étape : {Stage}, depuis {SinceStage.Elapsed.TotalSeconds:0} s ; armé depuis {SinceArming.Elapsed.TotalSeconds:0} s\n\n"
                + $"Dernière ligne vers le terminal :\n{Excerpt(ConsoleVolume.Last)}\n\n"
                + $"Exception du déclencheur :\n{evidence?.ToString() ?? "(aucune)"}\n");
        }
        catch
        {
            // Disque plein possible : la ligne du journal suffit.
        }
    }

    private static string Excerpt(string? line) =>
        line is null ? "(aucune)" : line.Length <= 2_000 ? line : line[..2_000] + "…";
}
