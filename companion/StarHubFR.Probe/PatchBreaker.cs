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
/// processus. Il ne retient que celles levées **directement dans le corps**
/// d'une méthode enveloppée (son nom porte <see cref="PatchCosts.WrapperId"/>) :
/// à la première chance, `TargetSite` et la pile ne voient que la méthode qui
/// lève, et l'enveloppe ne peut casser que ce corps. Une exception levée par
/// une méthode qu'il appelle, ou par le transpiler d'un autre mod, ne compte
/// pas. Pendant la pose des enveloppes (<see cref="Wrapping"/>), rien n'est
/// regardé : MonoMod y lève et rattrape lui-même des milliers d'exceptions
/// (« Type must derive from Delegate », `GetMethodHandle`, session v0.4.6), et
/// un IL refusé y est déjà rattrapé comme échec d'enveloppe.
///
/// Déclencheurs :
/// - une `InvalidProgramException` dans une enveloppe : IL refusé par le JIT ;
/// - plus de 10 000 exceptions dans des enveloppes en 10 secondes. Une enveloppe
///   fausse en lève des milliers par trame ; un patch qui lève et rattrape
///   légitimement une fois par tick reste loin en dessous. Le pic par fenêtre
///   s'écrit dans `patch-wraps.json` : le seuil se juge sur le parc ;
/// - plus de 8 millions de caractères vers le terminal en 10 secondes
///   (<see cref="ConsoleVolume"/>), quelle qu'en soit la cause — le symptôme de
///   la v0.4.5 ; une exception rattrapée n'écrit rien ;
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
/// Veille et retrait n'agissent que sans cadre de patch ouvert
/// (<see cref="ModCosts.PatchOnStack"/>) : `Exit` revient aussitôt une fois en
/// veille, un cadre ouvert ne dépilerait plus et la mesure des événements
/// s'arrêterait. Sinon, report au tick suivant.
///
/// Cause, étape et exception **du déclencheur qui a sauté** vont dans
/// `disjoncteur.txt`, et une ligne au journal. Un déclenchement à tort ne coûte
/// que la mesure des patches.
/// </summary>
internal static class PatchBreaker
{
    private const int WrappedExceptionLimit = 10_000;
    private const long ConsoleLimit = 8_000_000;
    private static readonly TimeSpan Window = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan AfterSaveLoaded = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan AfterArming = TimeSpan.FromMinutes(15);
    /// <summary>~10 s : une pile corrompue sans interruption déclarée ne reporte pas sans fin.</summary>
    private const int MaxDeferredTicks = 600;

    /// <summary>Pose des enveloppes en cours (<see cref="PatchCosts.WrapNew"/>) : exceptions ignorées.</summary>
    public static volatile bool Wrapping;

    private static IMonitor Monitor = null!;
    private static int WrappedExceptions;
    private static int WindowStartExceptions;
    private static readonly Stopwatch SinceWindow = new();
    private static long WindowStartChars;
    private static Exception? LastSeen;
    private static int PeakPerWindow;
    private static string? PeakSite;
    /// <summary>La preuve du déclencheur qui a sauté, pas d'un autre.</summary>
    private static Exception? Evidence;
    /// <summary>Cause urgente, posée depuis n'importe quel fil.</summary>
    private static string? Urgent;
    /// <summary>Cause sans danger, fil du jeu seulement.</summary>
    private static string? Calm;
    private static bool PauseDone;
    /// <summary>Fin de journée ou retour au titre vu depuis la cause sans danger.</summary>
    private static bool CalmDue;
    private static int DeferredTicks;
    private static readonly Stopwatch SinceArming = new();
    private static readonly Stopwatch SinceStage = new();
    private static readonly Stopwatch SinceSaveLoaded = new();
    private static string Stage = "";
    private static int Handled;
    private static bool Armed;

    /// <summary>Évite qu'une exception levée par le gestionnaire ne le rappelle.</summary>
    [ThreadStatic] private static bool InHandler;

    /// <summary>Pour `patch-wraps.json` : le plus d'exceptions vues en une fenêtre, et où.</summary>
    public static string? PeakDescription =>
        PeakPerWindow == 0 ? null : $"{PeakPerWindow} en {Window.TotalSeconds:0} s au plus ; la dernière : {PeakSite}";

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

    /// <summary>
    /// Tout fil, chaque exception du processus. `TargetSite` se résout par
    /// réflexion, et la pile en repli construit une chaîne : c'est le prix
    /// payé par exception hors pose des enveloppes.
    /// </summary>
    private static void OnException(object? sender, FirstChanceExceptionEventArgs e)
    {
        if (Wrapping || InHandler || Volatile.Read(ref Urgent) is not null) return;
        InHandler = true;
        try
        {
            Exception ex = e.Exception;
            // Le nom de la méthode de remplacement porte l'identifiant de
            // l'enveloppe (`UpdatePostfix_PatchedBy<…PatchCosts>`). La pile
            // en repli : une méthode dynamique peut rendre un TargetSite nul.
            string? site = ex.TargetSite?.Name ?? ex.StackTrace;
            if (site is null || !site.Contains(PatchCosts.WrapperId, StringComparison.Ordinal)) return;
            if (ex is InvalidProgramException)
            {
                Trip($"IL refusé par le JIT : {ex.Message}", ex);
                return;
            }
            Volatile.Write(ref LastSeen, ex);
            Interlocked.Increment(ref WrappedExceptions);
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

    /// <summary>Fil du jeu, à chaque tick : c'est ici que tout agit.</summary>
    public static void Poll()
    {
        if (!Armed || Handled != 0) return;
        CheckWindow();
        if (Calm is null)
        {
            if (ModCosts.Interrupted)
                Calm = $"mesure interrompue ({ModCosts.InterruptReason})";
            else if (SinceSaveLoaded.Elapsed >= AfterSaveLoaded || SinceArming.Elapsed >= AfterArming)
                Calm = "échéance de la mesure atteinte";
        }

        string? urgent = Volatile.Read(ref Urgent);
        bool calmPending = Calm is not null && (!PauseDone || CalmDue);
        if (urgent is null && !calmPending) return;
        if (!SafeToAct()) return;

        if (urgent is not null)
        {
            Finish(urgent, LogLevel.Warn);
            return;
        }
        if (!PauseDone)
        {
            PauseDone = true;
            PatchCosts.Pause(Calm!);
            const string outcome = "mesure arrêtée, enveloppes en veille jusqu'à la fin de la journée ou au retour au titre";
            WriteFile(Calm!, outcome, null);
            Monitor.Log($"Coût des patches : {Calm}, {outcome}.", LogLevel.Info);
        }
        if (CalmDue) Finish(Calm!, LogLevel.Info);
    }

    /// <summary>
    /// Fenêtre de 10 s : volume du terminal et exceptions dans les enveloppes.
    /// Le seuil se teste à chaque tick, le pic se relève en fin de fenêtre.
    /// </summary>
    private static void CheckWindow()
    {
        long written = ConsoleVolume.Written - WindowStartChars;
        if (written > ConsoleLimit)
            Trip($"{written / 1_000_000} millions de caractères vers le terminal en moins de {Window.TotalSeconds:0} s", null);
        int thrown = Volatile.Read(ref WrappedExceptions) - WindowStartExceptions;
        if (thrown > WrappedExceptionLimit)
            Trip($"{thrown} exceptions levées dans des patches enveloppés en moins de {Window.TotalSeconds:0} s", Volatile.Read(ref LastSeen));
        if (SinceWindow.Elapsed < Window) return;
        if (thrown > PeakPerWindow)
        {
            PeakPerWindow = thrown;
            Exception? last = Volatile.Read(ref LastSeen);
            // Même repli que le filtre : une méthode dynamique rend un TargetSite nul.
            string? where = last?.TargetSite?.Name ?? last?.StackTrace?.Split('\n')[0].Trim();
            PeakSite = last is null ? "?" : $"{last.GetType().Name} dans {where ?? "?"}";
        }
        WindowStartChars = ConsoleVolume.Written;
        WindowStartExceptions += thrown;
        SinceWindow.Restart();
    }

    /// <summary>
    /// Aucun cadre de patch ouvert, ou mesure déjà interrompue (sa pile ne
    /// compte plus). Sinon report, borné : une pile qui ne se vide jamais ne
    /// retient pas une urgence.
    /// </summary>
    private static bool SafeToAct()
    {
        if (ModCosts.Interrupted || !ModCosts.PatchOnStack() || ++DeferredTicks >= MaxDeferredTicks)
        {
            DeferredTicks = 0;
            return true;
        }
        return false;
    }

    /// <summary>Fin de journée, retour au titre : un gel ne s'y voit pas. Le retrait se fait au tick suivant.</summary>
    public static void CalmMoment()
    {
        if (Armed && Handled == 0 && Calm is not null) CalmDue = true;
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
                + $"Étape : {Stage}, depuis {SinceStage.Elapsed.TotalSeconds:0} s ; armé depuis {SinceArming.Elapsed.TotalSeconds:0} s\n"
                + $"Exceptions dans les enveloppes : {PeakDescription ?? "aucune"}\n\n"
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
