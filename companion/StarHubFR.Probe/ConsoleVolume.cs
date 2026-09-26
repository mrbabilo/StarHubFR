using System;
using System.IO;
using System.Text;
using System.Threading;

namespace StarHubFR.Probe;

/// <summary>
/// Compte ce qui part vers le terminal, sans rien y changer : le symptôme même
/// de la session v0.4.5 (~30 Go dans le terminal de SMAPI). Posé devant
/// `Console.Out` et `Console.Error`. SMAPI 4.5 n'y met aucun intercepteur
/// (pas de `SetOut` dans sa DLL, décompilée le 2026-09-26 : « Direct console
/// access » vient de l'analyse du code des mods) ; ses lignes passent par
/// `Console.Write`/`WriteLine` (`ColorfulConsoleWriter`), donc par ici.
///
/// Mesure la cause que les exceptions ne voient pas : une exception rattrapée
/// n'écrit rien (MonoMod en lève des milliers par seconde en posant des
/// patches, session v0.4.6), une écriture en boucle sans exception écrit tout.
/// </summary>
internal sealed class ConsoleVolume : TextWriter
{
    private static long Chars;
    private static string? LastLine;
    private static bool Installed;

    private readonly TextWriter Inner;

    private ConsoleVolume(TextWriter inner) => Inner = inner;

    /// <summary>Caractères écrits depuis le démarrage, tous fils confondus.</summary>
    public static long Written => Interlocked.Read(ref Chars);

    /// <summary>La dernière chaîne écrite : la ligne qui se répète, quand ça déborde.</summary>
    public static string? Last => Volatile.Read(ref LastLine);

    public static void Install()
    {
        if (Installed) return;
        Installed = true;
        Console.SetOut(new ConsoleVolume(Console.Out));
        Console.SetError(new ConsoleVolume(Console.Error));
    }

    public override Encoding Encoding => Inner.Encoding;

    public override void Write(char value)
    {
        Interlocked.Increment(ref Chars);
        Inner.Write(value);
    }

    public override void Write(string? value)
    {
        if (value is not null)
        {
            Interlocked.Add(ref Chars, value.Length);
            if (value.Length > 2) Volatile.Write(ref LastLine, value);
        }
        Inner.Write(value);
    }

    public override void Write(char[] buffer, int index, int count)
    {
        Interlocked.Add(ref Chars, count);
        Inner.Write(buffer, index, count);
    }

    // Chaque surcharge part telle quelle vers la même surcharge d'origine :
    // l'écrivain d'origine voit exactement les appels qu'il aurait vus.
    public override void Write(ReadOnlySpan<char> buffer)
    {
        Interlocked.Add(ref Chars, buffer.Length);
        Inner.Write(buffer);
    }

    public override void WriteLine(string? value)
    {
        if (value is not null)
        {
            Interlocked.Add(ref Chars, value.Length + 1);
            if (value.Length > 2) Volatile.Write(ref LastLine, value);
        }
        Inner.WriteLine(value);
    }

    public override void WriteLine(ReadOnlySpan<char> buffer)
    {
        Interlocked.Add(ref Chars, buffer.Length + 1);
        Inner.WriteLine(buffer);
    }

    public override void WriteLine()
    {
        Interlocked.Increment(ref Chars);
        Inner.WriteLine();
    }

    public override void Flush() => Inner.Flush();
}
