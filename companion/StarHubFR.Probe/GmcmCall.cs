using System;
using System.Linq;
using System.Reflection;

namespace StarHubFR.Probe;

/// <summary>
/// Appeler une méthode de l'API GMCM par réflexion. `MethodInfo.Invoke` ne
/// connaît pas les paramètres optionnels : il veut toute la signature, alors
/// qu'on ne renseigne que le début. Compter ces paramètres à la main a gardé la
/// page de la sonde hors du menu jusqu'à la 0.9.33 (`AddBoolOption` en a six).
/// </summary>
public static class GmcmCall
{
    /// <summary>La méthode publique `name` qui accepte `given` arguments, le
    /// reste de ses paramètres étant optionnel ; `null` si aucune ne convient.</summary>
    public static MethodInfo? Find(Type api, string name, int given) =>
        api.GetMethods().FirstOrDefault(method => method.Name == name && Accepts(method, given));

    /// <summary>Appelle `method` en complétant `given` par les valeurs par
    /// défaut de la signature.</summary>
    public static void Invoke(MethodInfo method, object target, object?[] given)
    {
        var parameters = method.GetParameters();
        var arguments = given.Concat(parameters.Skip(given.Length).Select(p => p.DefaultValue));
        method.Invoke(target, arguments.ToArray());
    }

    private static bool Accepts(MethodInfo method, int given)
    {
        var parameters = method.GetParameters();
        return parameters.Length >= given && parameters.Skip(given).All(p => p.IsOptional);
    }
}
