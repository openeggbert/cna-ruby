// SPDX-License-Identifier: MIT
using System;
using System.Globalization;
using System.Reflection;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Input;

internal static class GamePadReferenceProbe
{
    private static string Bits(float value)
    {
        return BitConverter.ToUInt32(BitConverter.GetBytes(value), 0).ToString("X8", CultureInfo.InvariantCulture);
    }

    private static string B(bool value) { return value ? "true" : "false"; }

    private static void Row(string group, string name, params object[] values)
    {
        Console.Write(group);
        Console.Write("|");
        Console.Write(name);
        foreach (object value in values)
        {
            Console.Write("|");
            Console.Write(Convert.ToString(value, CultureInfo.InvariantCulture));
        }
        Console.WriteLine();
    }

    private static void ButtonsRow(string name, Buttons flags)
    {
        GamePadButtons value = new GamePadButtons(flags);
        Row("GAMEPAD_BUTTONS", name,
            (int)value.A, (int)value.B, (int)value.Back, (int)value.X, (int)value.Y,
            (int)value.Start, (int)value.LeftShoulder, (int)value.LeftStick,
            (int)value.RightShoulder, (int)value.RightStick, (int)value.BigButton,
            value.GetHashCode(), value.ToString());
    }

    private static void TriggerRow(string name, float left, float right)
    {
        GamePadTriggers value = new GamePadTriggers(left, right);
        Row("GAMEPAD_TRIGGERS", name, Bits(value.Left), Bits(value.Right), value.GetHashCode(), value.ToString(),
            B(value.Equals(new GamePadTriggers(value.Left, value.Right))));
    }

    private static void ThumbRow(string name, Vector2 left, Vector2 right)
    {
        GamePadThumbSticks value = new GamePadThumbSticks(left, right);
        Row("GAMEPAD_THUMBSTICKS", name,
            Bits(value.Left.X), Bits(value.Left.Y), Bits(value.Right.X), Bits(value.Right.Y),
            value.GetHashCode(), value.ToString(),
            B(value.Equals(new GamePadThumbSticks(value.Left, value.Right))));
    }

    private static Vector2 DeadZoneStick(string methodName, int x, int y, GamePadDeadZone mode)
    {
        Type type = typeof(GamePadState).Assembly.GetType("Microsoft.Xna.Framework.Input.GamePadDeadZoneUtils", true);
        MethodInfo method = type.GetMethod(methodName, BindingFlags.Static | BindingFlags.NonPublic);
        return (Vector2)method.Invoke(null, new object[] { x, y, mode });
    }

    private static float DeadZoneTrigger(int value, GamePadDeadZone mode)
    {
        Type type = typeof(GamePadState).Assembly.GetType("Microsoft.Xna.Framework.Input.GamePadDeadZoneUtils", true);
        MethodInfo method = type.GetMethod("ApplyTriggerDeadZone", BindingFlags.Static | BindingFlags.NonPublic);
        return (float)method.Invoke(null, new object[] { value, mode });
    }

    private static void DeadZoneRow(string name, string method, int x, int y, GamePadDeadZone mode)
    {
        Vector2 value = DeadZoneStick(method, x, y, mode);
        Row("GAMEPAD_DEAD_ZONE", name, Bits(value.X), Bits(value.Y));
    }

    private static void StateRow(string name, GamePadState value, params Buttons[] queries)
    {
        object[] output = new object[5 + queries.Length * 2];
        output[0] = B(value.IsConnected);
        output[1] = value.PacketNumber;
        output[2] = value.GetHashCode();
        output[3] = value.ToString();
        output[4] = value.Buttons.ToString() + ";" + value.DPad.ToString() + ";" +
                    value.ThumbSticks.ToString() + ";" + value.Triggers.ToString();
        for (int i = 0; i < queries.Length; ++i)
        {
            output[5 + i * 2] = B(value.IsButtonDown(queries[i]));
            output[6 + i * 2] = B(value.IsButtonUp(queries[i]));
        }
        Row("GAMEPAD_STATE", name, output);
    }

    private static GamePadState WithPrivateState(GamePadState value, bool connected, int packet)
    {
        object boxed = value;
        Type type = typeof(GamePadState);
        type.GetField("_connected", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(boxed, connected);
        type.GetField("_packet", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(boxed, packet);
        return (GamePadState)boxed;
    }

    private static int VibrationWord(float value)
    {
        return unchecked((ushort)(short)(value * 65535f));
    }

    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;

        Row("GAMEPAD_ENUMS", "buttons",
            (int)Buttons.DPadUp, (int)Buttons.DPadDown, (int)Buttons.DPadLeft, (int)Buttons.DPadRight,
            (int)Buttons.Start, (int)Buttons.Back, (int)Buttons.LeftStick, (int)Buttons.RightStick,
            (int)Buttons.LeftShoulder, (int)Buttons.RightShoulder, (int)Buttons.BigButton,
            (int)Buttons.A, (int)Buttons.B, (int)Buttons.X, (int)Buttons.Y,
            (int)Buttons.RightThumbstickUp, (int)Buttons.RightThumbstickDown,
            (int)Buttons.RightThumbstickRight, (int)Buttons.RightThumbstickLeft,
            (int)Buttons.LeftThumbstickUp, (int)Buttons.LeftThumbstickDown,
            (int)Buttons.LeftThumbstickRight, (int)Buttons.LeftThumbstickLeft,
            (int)Buttons.RightTrigger, (int)Buttons.LeftTrigger);
        Row("GAMEPAD_ENUMS", "composition", (int)(Buttons.A | Buttons.B), (int)(Buttons)0, (int)(Buttons)0x400);
        Row("GAMEPAD_ENUMS", "dead_zone", (int)GamePadDeadZone.None,
            (int)GamePadDeadZone.IndependentAxes, (int)GamePadDeadZone.Circular);
        Row("GAMEPAD_ENUMS", "type", (int)GamePadType.Unknown, (int)GamePadType.GamePad,
            (int)GamePadType.Wheel, (int)GamePadType.ArcadeStick, (int)GamePadType.FlightStick,
            (int)GamePadType.DancePad, (int)GamePadType.Guitar, (int)GamePadType.AlternateGuitar,
            (int)GamePadType.DrumKit, (int)GamePadType.BigButtonPad);

        ButtonsRow("none", (Buttons)0);
        ButtonsRow("asymmetric", Buttons.A | Buttons.Back | Buttons.RightShoulder | Buttons.BigButton);
        ButtonsRow("virtual_ignored", Buttons.LeftThumbstickLeft | Buttons.RightTrigger);
        ButtonsRow("dense", Buttons.A | Buttons.B | Buttons.X | Buttons.Y | Buttons.Back | Buttons.Start |
            Buttons.LeftShoulder | Buttons.RightShoulder | Buttons.LeftStick | Buttons.RightStick | Buttons.BigButton);

        GamePadDPad dpad = new GamePadDPad(ButtonState.Pressed, ButtonState.Released,
            ButtonState.Pressed, ButtonState.Released);
        Row("GAMEPAD_DPAD", "asymmetric", (int)dpad.Up, (int)dpad.Down, (int)dpad.Right,
            (int)dpad.Left, dpad.GetHashCode(), dpad.ToString());
        GamePadDPad dpadNone = new GamePadDPad(ButtonState.Released, ButtonState.Released,
            ButtonState.Released, ButtonState.Released);
        Row("GAMEPAD_DPAD", "none", dpadNone.GetHashCode(), dpadNone.ToString(), B(dpad == dpad), B(dpad != dpadNone));

        TriggerRow("clamp", -1f, 2f);
        TriggerRow("ordinary", 0.5f, 1f);
        TriggerRow("nan_inf", float.NaN, float.PositiveInfinity);
        TriggerRow("negative_inf", float.NegativeInfinity, float.NegativeInfinity);
        TriggerRow("signed_zero", BitConverter.ToSingle(BitConverter.GetBytes(0x80000000u), 0), 0f);

        ThumbRow("zero", Vector2.Zero, Vector2.Zero);
        ThumbRow("square_clamp", new Vector2(2f, -2f), new Vector2(0.8f, 0.8f));
        ThumbRow("nonfinite", new Vector2(float.NaN, float.PositiveInfinity),
            new Vector2(float.NegativeInfinity, BitConverter.ToSingle(BitConverter.GetBytes(0x80000000u), 0)));

        DeadZoneRow("left_none_diagonal", "ApplyLeftStickDeadZone", 32767, 32767, GamePadDeadZone.None);
        DeadZoneRow("left_independent_inside", "ApplyLeftStickDeadZone", 7849, -7849, GamePadDeadZone.IndependentAxes);
        DeadZoneRow("left_independent_outside", "ApplyLeftStickDeadZone", 7850, -7850, GamePadDeadZone.IndependentAxes);
        DeadZoneRow("right_independent_outside", "ApplyRightStickDeadZone", 8690, -8690, GamePadDeadZone.IndependentAxes);
        DeadZoneRow("left_circular_inside", "ApplyLeftStickDeadZone", 5000, 5000, GamePadDeadZone.Circular);
        DeadZoneRow("left_circular_boundary", "ApplyLeftStickDeadZone", 7849, 0, GamePadDeadZone.Circular);
        DeadZoneRow("left_circular_outside", "ApplyLeftStickDeadZone", 7850, 0, GamePadDeadZone.Circular);
        DeadZoneRow("left_circular_diagonal", "ApplyLeftStickDeadZone", 32767, 32767, GamePadDeadZone.Circular);
        Row("GAMEPAD_DEAD_ZONE", "triggers", Bits(DeadZoneTrigger(30, GamePadDeadZone.IndependentAxes)),
            Bits(DeadZoneTrigger(31, GamePadDeadZone.IndependentAxes)),
            Bits(DeadZoneTrigger(30, GamePadDeadZone.None)), Bits(DeadZoneTrigger(255, GamePadDeadZone.None)));

        Vector2 leftThreshold = new Vector2(7850f / 32767f, -7850f / 32767f);
        Vector2 rightThreshold = new Vector2(8690f / 32767f, -8690f / 32767f);
        GamePadState components = new GamePadState(
            new GamePadThumbSticks(leftThreshold, rightThreshold),
            new GamePadTriggers(31f / 255f, 30f / 255f),
            new GamePadButtons(Buttons.A | Buttons.Back), dpad);
        StateRow("components", components, Buttons.A, Buttons.B, Buttons.DPadUp,
            Buttons.LeftThumbstickRight, Buttons.LeftThumbstickDown,
            Buttons.RightThumbstickRight, Buttons.RightThumbstickDown,
            Buttons.LeftTrigger, Buttons.RightTrigger, Buttons.A | Buttons.B,
            Buttons.A | Buttons.DPadUp | Buttons.LeftTrigger, (Buttons)0, (Buttons)0x400);

        GamePadState arrayNil = new GamePadState(Vector2.Zero, Vector2.Zero, 0f, 0f, (Buttons[])null);
        StateRow("array_nil", arrayNil, (Buttons)0, Buttons.A);
        GamePadState arrayCombined = new GamePadState(Vector2.Zero, Vector2.Zero, 0f, 0f,
            new Buttons[] { Buttons.A | Buttons.DPadRight, Buttons.A, Buttons.B });
        StateRow("array_combined_repeated", arrayCombined, Buttons.A, Buttons.B,
            Buttons.DPadRight, Buttons.A | Buttons.B | Buttons.DPadRight);

        GamePadState disconnected = WithPrivateState(arrayNil, false, 37);
        StateRow("private_disconnected_packet", disconnected, (Buttons)0);
        Row("GAMEPAD_STATE", "equality_fields", B(arrayNil == arrayNil), B(arrayNil == disconnected),
            B(arrayNil != disconnected), B(arrayNil.Equals((object)arrayNil)), B(arrayNil.Equals((object)null)));

        GamePadCapabilities caps = default(GamePadCapabilities);
        Row("GAMEPAD_CAPABILITIES", "default", (int)caps.GamePadType, B(caps.IsConnected),
            B(caps.HasAButton), B(caps.HasBackButton), B(caps.HasBButton), B(caps.HasDPadDownButton),
            B(caps.HasDPadLeftButton), B(caps.HasDPadRightButton), B(caps.HasDPadUpButton),
            B(caps.HasLeftShoulderButton), B(caps.HasLeftStickButton), B(caps.HasRightShoulderButton),
            B(caps.HasRightStickButton), B(caps.HasStartButton), B(caps.HasXButton), B(caps.HasYButton),
            B(caps.HasBigButton), B(caps.HasLeftXThumbStick), B(caps.HasLeftYThumbStick),
            B(caps.HasRightXThumbStick), B(caps.HasRightYThumbStick), B(caps.HasLeftTrigger),
            B(caps.HasRightTrigger), B(caps.HasLeftVibrationMotor), B(caps.HasRightVibrationMotor),
            B(caps.HasVoiceSupport));

        float[] vibration = { -1f, BitConverter.ToSingle(BitConverter.GetBytes(0x80000000u), 0),
            0f, 0.5f, 1f, 1.5f, float.NaN, float.PositiveInfinity, float.NegativeInfinity };
        foreach (float value in vibration)
        {
            Row("GAMEPAD_VIBRATION", Bits(value), VibrationWord(value));
        }
    }
}
