using System;
using System.Globalization;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

internal static class ViewportReferenceProbe
{
    private static float FromBits(uint bits)
    {
        return BitConverter.ToSingle(BitConverter.GetBytes(unchecked((int)bits)), 0);
    }

    private static string FloatValue(float value)
    {
        return value.ToString("R", CultureInfo.InvariantCulture) + "@" +
               unchecked((uint)BitConverter.ToInt32(BitConverter.GetBytes(value), 0)).ToString("X8");
    }

    private static void PrintVector(string name, Vector3 value)
    {
        Console.WriteLine(name + "|" + FloatValue(value.X) + "|" +
                          FloatValue(value.Y) + "|" + FloatValue(value.Z));
    }

    private static void PrintRectangle(string name, Rectangle value)
    {
        Console.WriteLine(name + "|" + value.X.ToString(CultureInfo.InvariantCulture) + "|" +
                          value.Y.ToString(CultureInfo.InvariantCulture) + "|" +
                          value.Width.ToString(CultureInfo.InvariantCulture) + "|" +
                          value.Height.ToString(CultureInfo.InvariantCulture));
    }

    private static void PrintFloat(string name, float value)
    {
        Console.WriteLine(name + "|" + FloatValue(value));
    }

    private static void PrintMatrix(string name, Matrix value)
    {
        Console.WriteLine(name + "|" + FloatValue(value.M11) + "|" + FloatValue(value.M12) + "|" +
                          FloatValue(value.M13) + "|" + FloatValue(value.M14) + "|" +
                          FloatValue(value.M21) + "|" + FloatValue(value.M22) + "|" +
                          FloatValue(value.M23) + "|" + FloatValue(value.M24) + "|" +
                          FloatValue(value.M31) + "|" + FloatValue(value.M32) + "|" +
                          FloatValue(value.M33) + "|" + FloatValue(value.M34) + "|" +
                          FloatValue(value.M41) + "|" + FloatValue(value.M42) + "|" +
                          FloatValue(value.M43) + "|" + FloatValue(value.M44));
    }

    private static Matrix MatrixWithW(float w)
    {
        Matrix value = Matrix.Identity;
        value.M44 = w;
        return value;
    }

    private static void Main()
    {
        Viewport viewport = new Viewport(13, -7, 641, 479);
        viewport.MinDepth = 0.2f;
        viewport.MaxDepth = 0.85f;

        PrintVector("PROJECT_IDENTITY",
                    viewport.Project(new Vector3(-0.25f, 0.5f, 0.75f),
                                     Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("UNPROJECT_IDENTITY",
                    viewport.Unproject(new Vector3(253.375f, 112.75f, 0.6875f),
                                       Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("PROJECT_DEPTH_ZERO",
                    viewport.Project(new Vector3(0.125f, -0.25f, 0.0f),
                                     Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("PROJECT_DEPTH_ONE",
                    viewport.Project(new Vector3(0.125f, -0.25f, 1.0f),
                                     Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("PROJECT_DEPTH_INTERIOR",
                    viewport.Project(new Vector3(0.125f, -0.25f, 0.3f),
                                     Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("PROJECT_DEPTH_OUTSIDE",
                    viewport.Project(new Vector3(0.125f, -0.25f, 1.5f),
                                     Matrix.Identity, Matrix.Identity, Matrix.Identity));

        Matrix world = new Matrix(
            1.25f, -0.375f, 0.5f, 0.0625f,
            0.2f, 0.875f, -0.45f, -0.03125f,
            -0.15f, 0.3f, 1.1f, 0.125f,
            3.5f, -2.25f, 4.75f, 1.0f);
        Matrix view = new Matrix(
            0.9f, 0.1f, -0.2f, 0.015625f,
            -0.05f, 1.05f, 0.125f, -0.0078125f,
            0.225f, -0.175f, 0.8f, 0.03125f,
            -1.5f, 2.75f, -3.25f, 1.0f);
        Matrix projection = new Matrix(
            1.1f, -0.075f, 0.04f, 0.2f,
            0.125f, 0.95f, -0.06f, -0.1f,
            -0.035f, 0.08f, 1.2f, 0.3f,
            0.15f, -0.2f, 0.25f, 0.9f);
        Vector3 objectSource = new Vector3(0.375f, -1.25f, 2.5f);
        PrintVector("PROJECT_NONTRIVIAL",
                    viewport.Project(objectSource, projection, view, world));
        PrintVector("UNPROJECT_NONTRIVIAL_DIRECT",
                    viewport.Unproject(new Vector3(333.25f, 211.5f, 0.625f),
                                       projection, view, world));
        Matrix diagnosticCombined = Matrix.Multiply(Matrix.Multiply(world, view), projection);
        Matrix diagnosticInverse = Matrix.Invert(diagnosticCombined);
        Vector3 diagnosticNormalized = new Vector3(333.25f, 211.5f, 0.625f);
        diagnosticNormalized.X = ((diagnosticNormalized.X - viewport.X) / viewport.Width) * 2.0f - 1.0f;
        diagnosticNormalized.Y = -(((diagnosticNormalized.Y - viewport.Y) / viewport.Height) * 2.0f - 1.0f);
        diagnosticNormalized.Z = (diagnosticNormalized.Z - viewport.MinDepth) /
                                 (viewport.MaxDepth - viewport.MinDepth);
        Vector3 diagnosticTransformed = Vector3.Transform(diagnosticNormalized, diagnosticInverse);
        float diagnosticW = diagnosticNormalized.X * diagnosticInverse.M14 +
                            diagnosticNormalized.Y * diagnosticInverse.M24 +
                            diagnosticNormalized.Z * diagnosticInverse.M34 + diagnosticInverse.M44;
        PrintMatrix("DIAGNOSTIC_COMBINED", diagnosticCombined);
        PrintMatrix("DIAGNOSTIC_INVERSE", diagnosticInverse);
        PrintVector("DIAGNOSTIC_NORMALIZED", diagnosticNormalized);
        PrintVector("DIAGNOSTIC_TRANSFORMED", diagnosticTransformed);
        PrintFloat("DIAGNOSTIC_W", diagnosticW);

        Vector3 projected = viewport.Project(objectSource, projection, view, world);
        PrintVector("ROUNDTRIP_OBJECT",
                    viewport.Unproject(projected, projection, view, world));
        Vector3 screenSource = new Vector3(411.75f, 83.125f, 0.42f);
        PrintVector("ROUNDTRIP_SCREEN",
                    viewport.Project(viewport.Unproject(screenSource, projection, view, world),
                                     projection, view, world));

        Viewport branchViewport = new Viewport(17, 23, 311, 197);
        Vector3 branchSource = new Vector3(0.25f, -0.375f, 0.625f);
        PrintVector("PROJECT_W_EXACT_ONE",
                    branchViewport.Project(branchSource, Matrix.Identity, Matrix.Identity,
                                           MatrixWithW(1.0f)));
        PrintVector("PROJECT_W_BELOW_ONE",
                    branchViewport.Project(branchSource, Matrix.Identity, Matrix.Identity,
                                           MatrixWithW(FromBits(0x3F7FFFFF))));
        PrintVector("PROJECT_W_ABOVE_ONE",
                    branchViewport.Project(branchSource, Matrix.Identity, Matrix.Identity,
                                           MatrixWithW(FromBits(0x3F800001))));
        PrintVector("PROJECT_W_TWO",
                    branchViewport.Project(branchSource, Matrix.Identity, Matrix.Identity,
                                           MatrixWithW(2.0f)));
        Vector3 branchScreen = new Vector3(211.375f, 158.4375f, 0.625f);
        PrintVector("UNPROJECT_W_EXACT_ONE",
                    branchViewport.Unproject(branchScreen, Matrix.Identity, Matrix.Identity,
                                             MatrixWithW(1.0f)));
        PrintVector("UNPROJECT_W_BELOW_ONE",
                    branchViewport.Unproject(branchScreen, Matrix.Identity, Matrix.Identity,
                                             MatrixWithW(FromBits(0x3F7FFFFF))));
        PrintVector("UNPROJECT_W_ABOVE_ONE",
                    branchViewport.Unproject(branchScreen, Matrix.Identity, Matrix.Identity,
                                             MatrixWithW(FromBits(0x3F800001))));
        PrintVector("UNPROJECT_W_HALF",
                    branchViewport.Unproject(branchScreen, Matrix.Identity, Matrix.Identity,
                                             MatrixWithW(0.5f)));

        Viewport depthViewport = new Viewport(-31, 47, -257, -129);
        depthViewport.MinDepth = 0.8f;
        depthViewport.MaxDepth = -0.3f;
        PrintVector("PROJECT_NEGATIVE_REVERSED",
                    depthViewport.Project(new Vector3(-0.6f, 0.35f, 1.25f),
                                          Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("UNPROJECT_NEGATIVE_REVERSED",
                    depthViewport.Unproject(new Vector3(-101.5f, -11.25f, 0.125f),
                                            Matrix.Identity, Matrix.Identity, Matrix.Identity));

        Viewport zero = new Viewport(5, -9, 0, 0);
        PrintVector("UNPROJECT_ZERO_EXTENT",
                    zero.Unproject(new Vector3(5.0f, -9.0f, 0.5f),
                                   Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("UNPROJECT_ZERO_WIDTH_OFFSET",
                    new Viewport(5, -9, 0, 17).Unproject(new Vector3(6.0f, -4.0f, 0.5f),
                                                        Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("UNPROJECT_ZERO_HEIGHT_OFFSET",
                    new Viewport(5, -9, 19, 0).Unproject(new Vector3(7.0f, -8.0f, 0.5f),
                                                        Matrix.Identity, Matrix.Identity, Matrix.Identity));
        zero.MinDepth = 0.25f;
        zero.MaxDepth = 0.25f;
        PrintVector("UNPROJECT_DEGENERATE_DEPTH",
                    zero.Unproject(new Vector3(6.0f, -8.0f, 0.25f),
                                   Matrix.Identity, Matrix.Identity, Matrix.Identity));

        Matrix singular = new Matrix();
        PrintVector("UNPROJECT_SINGULAR",
                    viewport.Unproject(new Vector3(101.0f, 77.0f, 0.4f),
                                       singular, Matrix.Identity, Matrix.Identity));
        PrintVector("PROJECT_SPECIAL_SOURCE",
                    viewport.Project(new Vector3(float.NaN, float.PositiveInfinity,
                                                 float.NegativeInfinity),
                                     Matrix.Identity, Matrix.Identity, Matrix.Identity));
        PrintVector("UNPROJECT_SPECIAL_SOURCE",
                    viewport.Unproject(new Vector3(float.PositiveInfinity, float.NaN,
                                                   float.NegativeInfinity),
                                       Matrix.Identity, Matrix.Identity, Matrix.Identity));

        PrintRectangle("TITLE_SAFE_ORDINARY", viewport.TitleSafeArea);
        PrintRectangle("TITLE_SAFE_ODD", new Viewport(-11, 23, 5, 7).TitleSafeArea);
        PrintRectangle("TITLE_SAFE_SMALL", new Viewport(3, 4, 0, 1).TitleSafeArea);
        PrintRectangle("TITLE_SAFE_NEGATIVE", new Viewport(7, -8, -9, -10).TitleSafeArea);

        Matrix leftAssociated = Matrix.Multiply(Matrix.Multiply(world, view), projection);
        Matrix rightAssociated = Matrix.Multiply(world, Matrix.Multiply(view, projection));
        PrintVector("ASSOCIATION_LEFT",
                    Vector3.Transform(objectSource, leftAssociated));
        PrintVector("ASSOCIATION_RIGHT",
                    Vector3.Transform(objectSource, rightAssociated));
    }
}
