using System;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics.PackedVector;

internal static class PackedVectorReferenceProbe
{
    private static float FromBits(int value)
    {
        return BitConverter.ToSingle(BitConverter.GetBytes(value), 0);
    }

    private static int Bits(float value)
    {
        return BitConverter.ToInt32(BitConverter.GetBytes(value), 0);
    }

    private static string VectorBits(Vector4 value)
    {
        return string.Format("{0:X8},{1:X8},{2:X8},{3:X8}",
            Bits(value.X), Bits(value.Y), Bits(value.Z), Bits(value.W));
    }

    private static void Dump(string id, ulong packed, IPackedVector value)
    {
        Console.WriteLine("VALUE|{0}|{1:X16}|{2}|{3}|{4}", id, packed,
            VectorBits(value.ToVector4()), value.GetHashCode(), value.ToString());
    }

    private static void Packed(string id, ulong value)
    {
        Console.WriteLine("PACKED|{0}|{1:X16}", id, value);
    }

    private static void Main()
    {
        Dump("Alpha8.ordinary", new Alpha8(0.5f).PackedValue, new Alpha8(0.5f));
        Packed("Alpha8.zero", new Alpha8(0.0f).PackedValue);
        Packed("Alpha8.minimum", new Alpha8(-1.0f).PackedValue);
        Packed("Alpha8.maximum", new Alpha8(1.0f).PackedValue);
        Packed("Alpha8.clampHigh", new Alpha8(2.0f).PackedValue);
        Packed("Alpha8.tieEvenLow", new Alpha8(0.5f / 255.0f).PackedValue);
        Packed("Alpha8.tieEvenHigh", new Alpha8(2.5f / 255.0f).PackedValue);

        Dump("Bgr565.ordinary", new Bgr565(0.25f, 0.5f, 0.75f).PackedValue, new Bgr565(0.25f, 0.5f, 0.75f));
        Packed("Bgr565.oneHotX", new Bgr565(1, 0, 0).PackedValue);
        Packed("Bgr565.oneHotY", new Bgr565(0, 1, 0).PackedValue);
        Packed("Bgr565.oneHotZ", new Bgr565(0, 0, 1).PackedValue);
        Packed("Bgr565.clamp", new Bgr565(-1, 2, -1).PackedValue);

        Dump("Bgra4444.ordinary", new Bgra4444(0.2f, 0.4f, 0.6f, 0.8f).PackedValue, new Bgra4444(0.2f, 0.4f, 0.6f, 0.8f));
        Packed("Bgra4444.oneHotX", new Bgra4444(1, 0, 0, 0).PackedValue);
        Packed("Bgra4444.oneHotY", new Bgra4444(0, 1, 0, 0).PackedValue);
        Packed("Bgra4444.oneHotZ", new Bgra4444(0, 0, 1, 0).PackedValue);
        Packed("Bgra4444.oneHotW", new Bgra4444(0, 0, 0, 1).PackedValue);

        Dump("Bgra5551.ordinary", new Bgra5551(0.25f, 0.5f, 0.75f, 0.5f).PackedValue, new Bgra5551(0.25f, 0.5f, 0.75f, 0.5f));
        Packed("Bgra5551.alphaBelow", new Bgra5551(0, 0, 0, FromBits(0x3effffff)).PackedValue);
        Packed("Bgra5551.alphaTie", new Bgra5551(0, 0, 0, 0.5f).PackedValue);
        Packed("Bgra5551.alphaAbove", new Bgra5551(0, 0, 0, FromBits(0x3f000001)).PackedValue);

        Dump("Byte4.ordinary", new Byte4(1, 127.5f, 254.5f, 300).PackedValue, new Byte4(1, 127.5f, 254.5f, 300));
        Packed("Byte4.raw", new Byte4(-1, 1, 128, 256).PackedValue);
        Packed("Byte4.ties", new Byte4(0.5f, 1.5f, 2.5f, 3.5f).PackedValue);

        Dump("HalfSingle.ordinary", new HalfSingle(1.0f / 3.0f).PackedValue, new HalfSingle(1.0f / 3.0f));
        Dump("HalfVector2.ordinary", new HalfVector2(1.0f, -2.0f).PackedValue, new HalfVector2(1.0f, -2.0f));
        Dump("HalfVector4.ordinary", new HalfVector4(1.0f, -2.0f, 0.5f, -0.0f).PackedValue, new HalfVector4(1.0f, -2.0f, 0.5f, -0.0f));
        Packed("HalfVector4.positionsX", new HalfVector4(1, 0, 0, 0).PackedValue);
        Packed("HalfVector4.positionsY", new HalfVector4(0, 1, 0, 0).PackedValue);
        Packed("HalfVector4.positionsZ", new HalfVector4(0, 0, 1, 0).PackedValue);
        Packed("HalfVector4.positionsW", new HalfVector4(0, 0, 0, 1).PackedValue);

        Dump("NormalizedByte2.ordinary", new NormalizedByte2(-1, 0.5f).PackedValue, new NormalizedByte2(-1, 0.5f));
        Dump("NormalizedByte4.ordinary", new NormalizedByte4(-1, -0.5f, 0.5f, 1).PackedValue, new NormalizedByte4(-1, -0.5f, 0.5f, 1));
        Packed("NormalizedByte4.endpoints", new NormalizedByte4(-2, 0, 1, 2).PackedValue);
        Packed("NormalizedByte4.ties", new NormalizedByte4(0.5f / 127.0f, 1.5f / 127.0f, -0.5f / 127.0f, -1.5f / 127.0f).PackedValue);

        Dump("NormalizedShort2.ordinary", new NormalizedShort2(-1, 0.5f).PackedValue, new NormalizedShort2(-1, 0.5f));
        Dump("NormalizedShort4.ordinary", new NormalizedShort4(-1, -0.5f, 0.5f, 1).PackedValue, new NormalizedShort4(-1, -0.5f, 0.5f, 1));
        Packed("NormalizedShort4.endpoints", new NormalizedShort4(-2, 0, 1, 2).PackedValue);
        Packed("NormalizedShort4.ties", new NormalizedShort4(0.5f / 32767.0f, 1.5f / 32767.0f, -0.5f / 32767.0f, -1.5f / 32767.0f).PackedValue);

        Dump("Rg32.ordinary", new Rg32(0.25f, 0.75f).PackedValue, new Rg32(0.25f, 0.75f));
        Packed("Rg32.oneHotX", new Rg32(1, 0).PackedValue);
        Packed("Rg32.oneHotY", new Rg32(0, 1).PackedValue);
        Packed("Rg32.clamp", new Rg32(-1, 2).PackedValue);

        Dump("Rgba1010102.ordinary", new Rgba1010102(0.25f, 0.5f, 0.75f, 0.5f).PackedValue, new Rgba1010102(0.25f, 0.5f, 0.75f, 0.5f));
        Packed("Rgba1010102.oneHotX", new Rgba1010102(1, 0, 0, 0).PackedValue);
        Packed("Rgba1010102.oneHotY", new Rgba1010102(0, 1, 0, 0).PackedValue);
        Packed("Rgba1010102.oneHotZ", new Rgba1010102(0, 0, 1, 0).PackedValue);
        Packed("Rgba1010102.oneHotW", new Rgba1010102(0, 0, 0, 1).PackedValue);
        Packed("Rgba1010102.alphaTies", new Rgba1010102(0, 1.0f / 6.0f, 0.5f, 5.0f / 6.0f).PackedValue);

        Dump("Rgba64.ordinary", new Rgba64(0.25f, 0.5f, 0.75f, 1).PackedValue, new Rgba64(0.25f, 0.5f, 0.75f, 1));
        Packed("Rgba64.oneHotX", new Rgba64(1, 0, 0, 0).PackedValue);
        Packed("Rgba64.oneHotY", new Rgba64(0, 1, 0, 0).PackedValue);
        Packed("Rgba64.oneHotZ", new Rgba64(0, 0, 1, 0).PackedValue);
        Packed("Rgba64.oneHotW", new Rgba64(0, 0, 0, 1).PackedValue);

        Dump("Short2.ordinary", new Short2(-32768, 32767).PackedValue, new Short2(-32768, 32767));
        Dump("Short4.ordinary", new Short4(-32768, -1.5f, 2.5f, 32768).PackedValue, new Short4(-32768, -1.5f, 2.5f, 32768));
        Packed("Short4.ties", new Short4(-0.5f, -1.5f, 0.5f, 1.5f).PackedValue);
        Packed("Short4.clamp", new Short4(-40000, 40000, float.NegativeInfinity, float.PositiveInfinity).PackedValue);

        IPackedVector interfaceValue;
        interfaceValue = new Alpha8(0); interfaceValue.PackFromVector4(new Vector4(-2, 0.5f, 2, 0.25f)); Dump("Interface.Alpha8", ((Alpha8) interfaceValue).PackedValue, interfaceValue);
        interfaceValue = new Bgr565(0, 0, 0); interfaceValue.PackFromVector4(new Vector4(-2, 0.5f, 2, 0.25f)); Dump("Interface.Bgr565", ((Bgr565) interfaceValue).PackedValue, interfaceValue);
        interfaceValue = new HalfSingle(0); interfaceValue.PackFromVector4(new Vector4(-2, 0.5f, 2, 0.25f)); Dump("Interface.HalfSingle", ((HalfSingle) interfaceValue).PackedValue, interfaceValue);
        interfaceValue = new NormalizedByte2(0, 0); interfaceValue.PackFromVector4(new Vector4(-2, 0.5f, 2, 0.25f)); Dump("Interface.NormalizedByte2", ((NormalizedByte2) interfaceValue).PackedValue, interfaceValue);
        interfaceValue = new Rg32(0, 0); interfaceValue.PackFromVector4(new Vector4(-2, 0.5f, 2, 0.25f)); Dump("Interface.Rg32", ((Rg32) interfaceValue).PackedValue, interfaceValue);
        interfaceValue = new Short2(0, 0); interfaceValue.PackFromVector4(new Vector4(-2, 0.5f, 2, 0.25f)); Dump("Interface.Short2", ((Short2) interfaceValue).PackedValue, interfaceValue);

        HalfVector4 hashBoundary = new HalfVector4(0, 0, 0, 0);
        hashBoundary.PackedValue = 0xFEDCBA9876543210UL;
        Dump("Hash.UInt64Boundary", hashBoundary.PackedValue, hashBoundary);

        float[] values = {
            0.0f, FromBits(unchecked((int) 0x80000000)),
            FromBits(0x00000001),
            FromBits(0x33000000),
            FromBits(0x33800000),
            FromBits(0x387fc000),
            FromBits(0x38800000),
            FromBits(0x3f801000),
            FromBits(0x3f803000),
            65504.0f, 65520.0f,
            float.PositiveInfinity, float.NegativeInfinity,
            FromBits(unchecked((int) 0x7fc12345)),
            FromBits(unchecked((int) 0xffc12345))
        };

        foreach (float value in values)
        {
            HalfSingle packed = new HalfSingle(value);
            Console.WriteLine(
                "HALF|{0:X8}|{1:X4}|{2:X8}|{3}|{4}",
                Bits(value), packed.PackedValue,
                Bits(packed.ToSingle()),
                packed.GetHashCode(), packed.ToString());
        }
    }
}
