using System;
using System.Globalization;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input.Touch;

// Reference observation fixture for Microsoft.Xna.Framework.Input.Touch.TouchLocation.
//
// TouchLocation is dependency-complete for cna-ruby (TouchLocationState and Vector2 are both
// complete managed types) but is blocked on BEHAVIOR_EVIDENCE: its Equals, GetHashCode, ToString
// and TryGetPreviousLocation semantics live in XNA IL, and the reconstructed Linux host carries
// only the pinned public metadata snapshot, not the original assemblies.
//
// Run this against the real Microsoft XNA Framework 4.0 Windows runtime and capture stdout. Each
// line is pipe separated and feeds behavior/xna40-touch-location-values.json as PURE_XNA_DERIVED
// observations. Nothing here may be guessed or hand-written: only real output counts.
//
//   csc /r:"%XNAGSv4%\References\Windows\x86\Microsoft.Xna.Framework.dll" touch_location_reference_probe.cs
//   touch_location_reference_probe.exe > touch-location.txt
internal static class TouchLocationReferenceProbe
{
    private static string Vector(Vector2 value)
    {
        return value.X.ToString("R", CultureInfo.InvariantCulture) + ";" +
               value.Y.ToString("R", CultureInfo.InvariantCulture);
    }

    private static void Print(string name, TouchLocation value)
    {
        TouchLocation previous;
        bool hasPrevious = value.TryGetPreviousLocation(out previous);

        Console.WriteLine(
            name + "|" +
            value.Id.ToString(CultureInfo.InvariantCulture) + "|" +
            ((int)value.State).ToString(CultureInfo.InvariantCulture) + "|" +
            Vector(value.Position) + "|" +
            value.GetHashCode().ToString(CultureInfo.InvariantCulture) + "|" +
            value.ToString() + "|" +
            hasPrevious.ToString(CultureInfo.InvariantCulture) + "|" +
            previous.Id.ToString(CultureInfo.InvariantCulture) + "|" +
            ((int)previous.State).ToString(CultureInfo.InvariantCulture) + "|" +
            Vector(previous.Position));
    }

    private static void Compare(string name, TouchLocation left, TouchLocation right)
    {
        Console.WriteLine(
            "cmp:" + name + "|" +
            left.Equals(right).ToString(CultureInfo.InvariantCulture) + "|" +
            left.Equals((object)right).ToString(CultureInfo.InvariantCulture) + "|" +
            (left == right).ToString(CultureInfo.InvariantCulture) + "|" +
            (left != right).ToString(CultureInfo.InvariantCulture));
    }

    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

        TouchLocation defaultValue = default(TouchLocation);
        TouchLocation pressed = new TouchLocation(3, TouchLocationState.Pressed, new Vector2(12.5f, -7.25f));
        TouchLocation moved = new TouchLocation(3, TouchLocationState.Moved, new Vector2(40.0f, 11.0f),
                                                TouchLocationState.Pressed, new Vector2(12.5f, -7.25f));
        TouchLocation released = new TouchLocation(3, TouchLocationState.Released, new Vector2(40.0f, 11.0f),
                                                   TouchLocationState.Moved, new Vector2(40.0f, 11.0f));

        // Whether the three argument constructor records a previous location at all, and what the
        // out parameter holds when it does not, is exactly the unknown this probe settles.
        Print("default", defaultValue);
        Print("pressed", pressed);
        Print("moved", moved);
        Print("released", released);

        // Does a declared Invalid previous state still report a previous location?
        Print("invalidPrevious", new TouchLocation(9, TouchLocationState.Moved, new Vector2(1.0f, 2.0f),
                                                   TouchLocationState.Invalid, Vector2.Zero));

        // Undeclared raw state and hostile numeric values.
        Print("unknownState", new TouchLocation(-1, (TouchLocationState)12345, new Vector2(float.NaN, float.NegativeInfinity)));
        Print("extremes", new TouchLocation(Int32.MinValue, TouchLocationState.Invalid,
                                            new Vector2(float.MaxValue, float.Epsilon)));
        Print("negativeZero", new TouchLocation(0, TouchLocationState.Pressed, new Vector2(-0.0f, 0.0f)));

        // Which components participate in equality: does the previous location count?
        Compare("identical", pressed, new TouchLocation(3, TouchLocationState.Pressed, new Vector2(12.5f, -7.25f)));
        Compare("differentId", pressed, new TouchLocation(4, TouchLocationState.Pressed, new Vector2(12.5f, -7.25f)));
        Compare("differentState", pressed, new TouchLocation(3, TouchLocationState.Moved, new Vector2(12.5f, -7.25f)));
        Compare("differentPosition", pressed, new TouchLocation(3, TouchLocationState.Pressed, new Vector2(12.5f, 0.0f)));
        Compare("samePresentDifferentPrevious", moved,
                new TouchLocation(3, TouchLocationState.Moved, new Vector2(40.0f, 11.0f),
                                  TouchLocationState.Invalid, Vector2.Zero));
        Compare("signedZeroPosition", new TouchLocation(0, TouchLocationState.Pressed, new Vector2(-0.0f, 0.0f)),
                new TouchLocation(0, TouchLocationState.Pressed, new Vector2(0.0f, 0.0f)));
        Compare("nanPosition", new TouchLocation(0, TouchLocationState.Pressed, new Vector2(float.NaN, 0.0f)),
                new TouchLocation(0, TouchLocationState.Pressed, new Vector2(float.NaN, 0.0f)));

        Console.WriteLine("equalsObject:null|" + pressed.Equals(null).ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("equalsObject:foreign|" + pressed.Equals("touch").ToString(CultureInfo.InvariantCulture));
    }
}
