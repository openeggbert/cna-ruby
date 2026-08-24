using System;
using System.Globalization;
using Microsoft.Xna.Framework.Graphics;

internal static class VertexElementReferenceProbe
{
    private static void Print(string name, VertexElement value)
    {
        Console.WriteLine(
            name + "|" + value.Offset.ToString(CultureInfo.InvariantCulture) + "|" +
            ((int)value.VertexElementFormat).ToString(CultureInfo.InvariantCulture) + "|" +
            ((int)value.VertexElementUsage).ToString(CultureInfo.InvariantCulture) + "|" +
            value.UsageIndex.ToString(CultureInfo.InvariantCulture) + "|" +
            value.GetHashCode().ToString(CultureInfo.InvariantCulture) + "|" + value.ToString());
    }

    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Print("zero", default(VertexElement));
        Print("ordinary", new VertexElement(12, VertexElementFormat.Vector3,
                                             VertexElementUsage.TextureCoordinate, 7));
        Print("negative", new VertexElement(-16, VertexElementFormat.HalfVector4,
                                             VertexElementUsage.Tangent, -3));
        Print("unknown", new VertexElement(123, (VertexElementFormat)12345,
                                            (VertexElementUsage)(-23456), -456));
        Print("minmax", new VertexElement(Int32.MinValue, VertexElementFormat.HalfVector4,
                                          VertexElementUsage.TessellateFactor, Int32.MaxValue));
        Print("collision", new VertexElement(1, VertexElementFormat.Vector3,
                                              VertexElementUsage.Normal, 0));
    }
}
