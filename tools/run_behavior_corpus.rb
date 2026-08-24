# frozen_string_literal: true

require "json"
require_relative "../lib/cna"

F = Microsoft::Xna::Framework

def vector(value) = F::Vector2.new(*value)
def vector3(value) = F::Vector3.new(*value)
def vector4(value) = F::Vector4.new(*value)
def rectangle(value) = F::Rectangle.new(*value)
def color(value) = F::Color.new(*value)
def box(value) = F::BoundingBox.new(vector3(value[0]), vector3(value[1]))
def sphere(value) = F::BoundingSphere.new(vector3(value[0]), value[1])
def vector_result(value) = [value.X, value.Y]
def vector3_result(value) = [value.X, value.Y, value.Z]
def vector4_result(value) = [value.X, value.Y, value.Z, value.W]
def quaternion_result(value) = [value.X, value.Y, value.Z, value.W]
def matrix_result(value) = (1..4).flat_map { |row| (1..4).map { |column| value.public_send("M#{row}#{column}") } }
def rectangle_result(value) = [value.X, value.Y, value.Width, value.Height]
def color_result(value) = [value.R, value.G, value.B, value.A]
def hex32(value)
  narrowed = CNA::Runtime::Numeric.f32(value)
  if narrowed.nan?
    sign = [narrowed].pack("E").unpack1("Q<") >> 63
    return sign.zero? ? "7FC00000" : "FFC00000"
  end
  [narrowed].pack("e").unpack1("L<").to_s(16).upcase.rjust(8, "0")
end
def hex_values(values) = values.map { |value| hex32(value) }
def float_from_bits(value) = [value].pack("L").unpack1("f")

def equivalent?(actual, expected)
  if expected.instance_of?(Array)
    return actual.instance_of?(Array) && actual.length == expected.length && actual.zip(expected).all? { |left, right| equivalent?(left, right) }
  end
  return (actual.instance_of?(Integer) || actual.instance_of?(Float)) && (actual.to_f - expected).abs <= 1.0e-7 if expected.instance_of?(Float)

  actual == expected
end

def behavior_group(item)
  id = item.fetch("id")
  return "BOUNDING_BOX" if id.start_with?("box.")
  return "BOUNDING_SPHERE" if id.start_with?("sphere.")
  return "BOUNDING_FRUSTUM" if id.start_with?("frustum.")
  return "MATHHELPER" if id.start_with?("math.", "mathhelper.")
  return "VECTOR2" if id.start_with?("vector2.")
  return "VECTOR3" if id.start_with?("vector3.")
  return "VECTOR4" if id.start_with?("vector4.")
  return "QUATERNION" if id.start_with?("quaternion.")
  return "MATRIX" if id.start_with?("matrix.")
  return "PLANE" if id.start_with?("plane.")
  return "RAY" if id.start_with?("ray.")
  return "BINARY32" if id.start_with?("vector.scalar.", "float32.")
  return "CROSS_GEOMETRY" if id.start_with?("geometry.", "value.")

  id.split(".").first.upcase
end

def execute(item)
  args = item.fetch("args")
  case item.fetch("operation")
  when "MathHelper.Clamp" then F::MathHelper.Clamp(*args)
  when "MathHelper.Lerp" then F::MathHelper.Lerp(*args)
  when "MathHelper.Barycentric" then F::MathHelper.Barycentric(*args)
  when "MathHelper.CatmullRom" then F::MathHelper.CatmullRom(*args)
  when "MathHelper.Hermite" then F::MathHelper.Hermite(*args)
  when "MathHelper.SmoothStep" then F::MathHelper.SmoothStep(*args)
  when "MathHelper.WrapAngle" then F::MathHelper.WrapAngle(*args)
  when "MathHelper.ToDegrees" then F::MathHelper.ToDegrees(*args)
  when "Vector2.Add" then vector_result(F::Vector2.Add(vector(args[0]), vector(args[1])))
  when "Vector2.Dot" then F::Vector2.Dot(vector(args[0]), vector(args[1]))
  when "Vector2.Normalize" then vector_result(F::Vector2.Normalize(vector(args[0])))
  when "Vector2.Reflect" then vector_result(F::Vector2.Reflect(vector(args[0]), vector(args[1])))
  when "Vector2.Barycentric" then vector_result(F::Vector2.Barycentric(vector(args[0]), vector(args[1]), vector(args[2]), args[3], args[4]))
  when "Vector2.Transform" then vector_result(F::Vector2.Transform(vector(args[0]), F::Matrix.CreateTranslation(*args[1])))
  when "Vector2.ZeroFresh"
    left = F::Vector2.Zero; right = F::Vector2.Zero; !left.equal?(right)
  when "Vector3.Cross" then vector3_result(F::Vector3.Cross(vector3(args[0]), vector3(args[1])))
  when "Vector3.Distance" then F::Vector3.Distance(vector3(args[0]), vector3(args[1]))
  when "Vector3.Reflect" then vector3_result(F::Vector3.Reflect(vector3(args[0]), vector3(args[1])))
  when "Vector3.TransformNormal" then vector3_result(F::Vector3.TransformNormal(vector3(args[0]), F::Matrix.CreateScale(*args[1])))
  when "Vector3.SmoothStep" then vector3_result(F::Vector3.SmoothStep(vector3(args[0]), vector3(args[1]), args[2]))
  when "Vector4.Dot" then F::Vector4.Dot(vector4(args[0]), vector4(args[1]))
  when "Vector4.Hermite" then vector4_result(F::Vector4.Hermite(vector4(args[0]), vector4(args[1]), vector4(args[2]), vector4(args[3]), args[4]))
  when "Vector4.Transform" then vector4_result(F::Vector4.Transform(vector4(args[0]), F::Matrix.CreateTranslation(*args[1])))
  when "Quaternion.AxisAngleZero" then quaternion_result(F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, 0))
  when "Quaternion.YawPitchRoll" then quaternion_result(F::Quaternion.CreateFromYawPitchRoll(*args))
  when "Quaternion.Concatenate"
    quaternion_result(F::Quaternion.Concatenate(F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitX, args[0]), F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, args[1])))
  when "Quaternion.SlerpIdentity" then quaternion_result(F::Quaternion.Slerp(F::Quaternion.Identity, F::Quaternion.CreateFromAxisAngle(F::Vector3.UnitY, args[0]), args[1]))
  when "Quaternion.FromMatrix" then quaternion_result(F::Quaternion.CreateFromRotationMatrix(F::Matrix.CreateRotationY(args[0])))
  when "Matrix.Translation"
    value = F::Matrix.CreateTranslation(*args); [value.M41, value.M42, value.M43, value.M44]
  when "Matrix.MultiplyTranslations"
    value = F::Matrix.CreateTranslation(1, 2, 3) * F::Matrix.CreateTranslation(4, 5, 6); [value.M41, value.M42, value.M43, value.M44]
  when "Matrix.InverseProduct"
    value = F::Matrix.CreateScale(*args[0]) * F::Matrix.CreateTranslation(*args[1]); matrix_result(value * F::Matrix.Invert(value))
  when "Matrix.SingularInverseNaN" then matrix_result(F::Matrix.Invert(F::Matrix.new)).all?(&:nan?)
  when "Matrix.RotationY"
    value = F::Matrix.CreateRotationY(args[0]); [value.M11, value.M13, value.M31, value.M33]
  when "Matrix.PerspectiveInfinity"
    value = F::Matrix.CreatePerspective(args[0], args[1], args[2], Float::INFINITY); [value.M33.nan?, value.M43.nan?]
  when "Matrix.Decompose"
    success, scale, rotation, translation = (F::Matrix.CreateScale(*args[0]) * F::Matrix.CreateTranslation(*args[1])).Decompose
    [success, *vector3_result(scale), *quaternion_result(rotation), *vector3_result(translation)]
  when "Matrix.Billboard"
    value = F::Matrix.CreateBillboard(vector3(args[0]), vector3(args[1]), vector3(args[2]), nil)
    [value.M11, value.M22, value.M33, *vector3_result(value.Translation)]
  when "Matrix.Orthographic"
    value = F::Matrix.CreateOrthographic(*args); [value.M11, value.M22, value.M33, value.M43, value.M44]
  when "Color.Bytes" then color_result(color(args))
  when "Color.Packed" then color(args).PackedValue
  when "Color.Lerp" then color_result(F::Color.Lerp(color(args[0]), color(args[1]), args[2]))
  when "Color.Multiply" then color_result(F::Color.Multiply(color(args[0]), args[1]))
  when "Rectangle.Contains" then F::Rectangle.new(*args[0, 4]).Contains(args[4], args[5])
  when "Rectangle.Intersect" then rectangle_result(F::Rectangle.Intersect(rectangle(args[0]), rectangle(args[1])))
  when "Rectangle.Union" then rectangle_result(F::Rectangle.Union(rectangle(args[0]), rectangle(args[1])))
  when "Rectangle.Inflate"
    value = rectangle(args[0]); value.Inflate(*args[1]); rectangle_result(value)
  when "Rectangle.Offset"
    value = rectangle(args[0]); value.Offset(*args[1]); rectangle_result(value)
  when "Point.Equal" then F::Point.new(args[0], args[1]) == F::Point.new(args[2], args[3])
  when "Point.ZeroFresh" then !F::Point.Zero.equal?(F::Point.Zero)
  when "Plane.Normalize"
    value = F::Plane.new(vector3(args[0]), args[1]); result = F::Plane.Normalize(value); [*vector3_result(result.Normal), result.D]
  when "Plane.DotCoordinate" then F::Plane.new(vector3(args[0]), args[1]).DotCoordinate(vector3(args[2]))
  when "Plane.Box" then F::Plane.new(vector3(args[0]), args[1]).Intersects(box(args[2])).to_i
  when "Plane.Sphere" then F::Plane.new(vector3(args[0]), args[1]).Intersects(sphere(args[2])).to_i
  when "Ray.Box" then F::Ray.new(vector3(args[0]), vector3(args[1])).Intersects(box(args[2]))
  when "Ray.Sphere" then F::Ray.new(vector3(args[0]), vector3(args[1])).Intersects(sphere(args[2]))
  when "Ray.Plane" then F::Ray.new(vector3(args[0]), vector3(args[1])).Intersects(F::Plane.new(vector3(args[2]), args[3]))
  when "BoundingBox.ContainsPoint" then box(args[0]).Contains(vector3(args[1])).to_i
  when "BoundingBox.ContainsSphere" then box(args[0]).Contains(sphere(args[1])).to_i
  when "BoundingBox.Merge"
    value = F::BoundingBox.CreateMerged(box(args[0]), box(args[1])); [*vector3_result(value.Min), *vector3_result(value.Max)]
  when "BoundingSphere.ContainsPoint" then sphere(args[0]).Contains(vector3(args[1])).to_i
  when "BoundingSphere.Merge"
    value = F::BoundingSphere.CreateMerged(sphere(args[0]), sphere(args[1])); [*vector3_result(value.Center), value.Radius]
  when "BoundingSphere.Transform"
    value = sphere(args[0]).Transform(F::Matrix.CreateScale(*args[1]) * F::Matrix.CreateTranslation(*args[2])); [*vector3_result(value.Center), value.Radius]
  when "Frustum.ContainsPoint", "Frustum.ContainsBox", "Frustum.IntersectsSphere", "Frustum.Ray", "Frustum.Corners"
    frustum = F::BoundingFrustum.new(F::Matrix.CreatePerspectiveFieldOfView(F::MathHelper::PiOver2, 1, 1, 10))
    case item.fetch("operation")
    when "Frustum.ContainsPoint" then frustum.Contains(vector3(args[0])).to_i
    when "Frustum.ContainsBox" then frustum.Contains(box(args[0])).to_i
    when "Frustum.IntersectsSphere" then frustum.Intersects(sphere(args[0]))
    when "Frustum.Ray" then frustum.Intersects(F::Ray.new(vector3(args[0]), vector3(args[1])))
    when "Frustum.Corners" then [frustum.GetCorners.length, frustum.GetCorners[0].Z, frustum.GetCorners[4].Z]
    end
  when "Golden.Vector2NormalizeZero" then hex_values(vector_result(F::Vector2.Normalize(F::Vector2.Zero)))
  when "Golden.Vector3NormalizeZero" then hex_values(vector3_result(F::Vector3.Normalize(F::Vector3.Zero)))
  when "Golden.Vector4NormalizeZero" then hex_values(vector4_result(F::Vector4.Normalize(F::Vector4.Zero)))
  when "Golden.VectorDivide" then hex_values([(F::Vector2.new(3) / 7).X, (F::Vector3.new(7) / 3).X, (F::Vector4.new(12_345.67) / 3).X, (F::Matrix.Identity / 3).M11])
  when "Golden.QuaternionZero" then hex_values([*quaternion_result(F::Quaternion.Normalize(F::Quaternion.new)), *quaternion_result(F::Quaternion.Inverse(F::Quaternion.new))])
  when "Golden.QuaternionProducts"
    yaw = F::Quaternion.CreateFromAxisAngle(F::Vector3.Up, 0.7); pitch = F::Quaternion.CreateFromAxisAngle(F::Vector3.Right, -0.4)
    grouped = F::Quaternion.new(45_889.05859375, -42_412.4453125, 96_034.96875, -76_386.84375) * F::Quaternion.new(-16_375.435546875, 51_428.1875, -69_603.09375, -2_207.3798828125)
    hex_values([*quaternion_result(yaw * pitch), *quaternion_result(grouped), *quaternion_result(F::Quaternion.Concatenate(yaw, pitch)), *vector3_result(F::Vector3.Transform(F::Vector3.new(1.25, -2.5, 3.75), yaw * pitch))])
  when "Golden.MatrixTransforms"
    matrix = F::Matrix.CreateScale(2, 3, 4) * F::Matrix.CreateRotationY(0.25) * F::Matrix.CreateTranslation(5, 6, 7)
    hex_values([*vector_result(F::Vector2.Transform(F::Vector2.new(1.5, -2), matrix)), *vector3_result(F::Vector3.Transform(F::Vector3.new(1.5, -2, 0.25), matrix)), *vector4_result(F::Vector4.Transform(F::Vector4.new(1.5, -2, 0.25, 1), matrix))])
  when "Golden.PlaneTransform"
    value = F::Plane.Transform(F::Plane.new(F::Vector3.Up, -2), F::Matrix.CreateTranslation(0, 5, 0)); hex_values([*vector3_result(value.Normal), value.D])
  when "Golden.NaNEquality"
    vector_value = F::Vector2.new(Float::NAN, 0); matrix = F::Matrix.Identity; matrix.M11 = Float::NAN
    [vector_value.Equals(vector_value), vector_value == vector_value, matrix.Equals(matrix), matrix == matrix]
  when "Golden.HashCodes" then [F::Vector3.new(1, 2, 3).GetHashCode, F::Matrix.Identity.GetHashCode, F::Point.new(1, 2).GetHashCode, F::Rectangle.new(1, 2, 3, 4).GetHashCode]
  when "Golden.MathEdges"
    [hex32(F::MathHelper.Clamp(0, 2, 1)), hex32(F::MathHelper.WrapAngle(123_456.789)), hex32(F::MathHelper.CatmullRom(-10, -10, -10, -7, 0.3)), hex32(F::MathHelper.Hermite(-10, -10, -10, -10, 1.1)), F::MathHelper.Hermite(1, Float::INFINITY, 2, 0, 0).nan?]
  when "Golden.VectorEdges"
    nan = float_from_bits(0xFFC00000); minimum = F::Vector3.Min(F::Vector3.new(nan, 1, nan), F::Vector3.new(7, nan, nan)); clamped = F::Vector3.Clamp(F::Vector3.Zero, F::Vector3.new(2), F::Vector3.new(1))
    hex_values([*vector3_result(minimum), *vector3_result(clamped)])
  when "Golden.QuaternionEdges"
    yaw = F::Quaternion.CreateFromAxisAngle(F::Vector3.Up, 0.7); pitch = F::Quaternion.CreateFromAxisAngle(F::Vector3.Right, -0.4)
    hex_values([*quaternion_result(F::Quaternion.Slerp(yaw, pitch, 0.37)), *quaternion_result(F::Quaternion.CreateFromAxisAngle(F::Vector3.Up, 123_456.789)), *quaternion_result(F::Quaternion.CreateFromRotationMatrix(F::Matrix.CreateRotationY(0.7)))])
  when "Golden.MatrixEdges"
    large = F::Matrix.CreateRotationY(123_456.789); perspective = F::Matrix.CreatePerspective(4, 3, 0.1, Float::INFINITY)
    mirrored = F::Matrix.CreateScale(-2, 3, 4) * F::Matrix.CreateRotationY(0.25) * F::Matrix.CreateTranslation(5, 6, 7); ok, scale, rotation, translation = mirrored.Decompose
    [hex32(large.M11), hex32(large.M31), hex32(perspective.M33), hex32(perspective.M43), ok, *hex_values([*vector3_result(scale), *quaternion_result(rotation), *vector3_result(translation)]), *hex_values([(-F::Vector4.Zero).X, (-F::Quaternion.new).X, (-F::Matrix.new).M11])]
  when "Golden.MatrixDegenerate"
    billboard = F::Matrix.CreateConstrainedBillboard(F::Vector3.new(0, 10, 0), F::Vector3.Zero, F::Vector3.new(0, 2, 0), nil, nil)
    shadow = F::Matrix.CreateShadow(F::Vector3.Forward, F::Plane.new(F::Vector3.Zero, 0)); plane = F::Plane.new(F::Vector3.new(2, 0, 0), 4); reflection = F::Matrix.CreateReflection(plane); look = F::Matrix.CreateLookAt(F::Vector3.Zero, F::Vector3.Zero, F::Vector3.Up)
    [*hex_values([billboard.M11, billboard.M22, billboard.M33]), shadow.M11.nan?, shadow.M44.nan?, *hex_values([plane.Normal.X, plane.D, reflection.M11, reflection.M41]), *hex_values(matrix_result(look))]
  when "Golden.PlaneEdges"
    degenerate = F::Plane.new(F::Vector3.Zero, F::Vector3.Zero, F::Vector3.Zero); near = F::Plane.Normalize(F::Plane.new(F::Vector3.new(0.6, 0.79999995, 0), 2)); coplanar = F::Plane.new(F::Vector3.Zero, 0).Intersects(F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1)))
    [*hex_values([*vector3_result(degenerate.Normal), degenerate.D, *vector3_result(near.Normal), near.D]), coplanar.to_i]
  when "Golden.GeometryEdges"
    volume = F::BoundingBox.new(F::Vector3.new(-1), F::Vector3.new(1)); nan_box = F::BoundingBox.new(F::Vector3.new(Float::NAN, -1, -1), F::Vector3.new(Float::NAN, 1, 1)); unit = F::BoundingSphere.new(F::Vector3.Zero, 1)
    [volume.Contains(F::Vector3.new(Float::NAN, 0, 0)).to_i, volume.Intersects(nan_box), unit.Contains(F::Vector3.UnitX).to_i, unit.Intersects(F::BoundingSphere.new(F::Vector3.new(2, 0, 0), 1)), F::Ray.new(F::Vector3.new(2, 0, 0), F::Vector3.new(-5e-7, 0, 0)).Intersects(volume), F::Ray.new(F::Vector3.Zero, F::Vector3.new(5e-6, 1, 0)).Intersects(F::Plane.new(F::Vector3.UnitX, -1))]
  when "Golden.FrustumPlanesCorners"
    projection = F::Matrix.CreatePerspectiveFieldOfView(F::MathHelper::PiOver4, 4.0 / 3.0, 1, 10); frustum = F::BoundingFrustum.new(F::Matrix.CreateLookAt(F::Vector3.new(0, 0, 5), F::Vector3.Zero, F::Vector3.Up) * projection); corners = frustum.GetCorners
    hex_values([*vector3_result(frustum.Near.Normal), frustum.Near.D, *vector3_result(frustum.Top.Normal), frustum.Top.D, *vector3_result(corners[0]), *vector3_result(corners[6])])
  when "Golden.FrustumRelations"
    projection = F::Matrix.CreatePerspectiveFieldOfView(F::MathHelper::PiOver4, 4.0 / 3.0, 1, 10); frustum = F::BoundingFrustum.new(F::Matrix.CreateLookAt(F::Vector3.new(0, 0, 5), F::Vector3.Zero, F::Vector3.Up) * projection); distant = F::BoundingFrustum.new(F::Matrix.CreateLookAt(F::Vector3.new(100, 0, 5), F::Vector3.new(100, 0, 0), F::Vector3.Up) * projection)
    [frustum.Contains(F::Vector3.Zero).to_i, frustum.Contains(F::Vector3.new(0, 0, 6)).to_i, frustum.Contains(F::BoundingBox.new(F::Vector3.new(-0.5), F::Vector3.new(0.5))).to_i, frustum.Contains(F::BoundingSphere.new(F::Vector3.Zero, 0.5)).to_i, frustum.Intersects(F::BoundingBox.new(F::Vector3.new(-0.5), F::Vector3.new(0.5))), frustum.Intersects(F::BoundingBox.new(F::Vector3.new(100), F::Vector3.new(101))), frustum.Intersects(F::BoundingSphere.new(F::Vector3.Zero, 0.5)), frustum.Intersects(F::BoundingSphere.new(F::Vector3.new(100), 0.5)), frustum.Intersects(distant), hex32(frustum.Intersects(F::Ray.new(F::Vector3.new(0, 0, 20), F::Vector3.Forward)))]
  when "Float32.NegativeZero"
    value = CNA::Runtime::Numeric.f32(-0.0)
    value.zero? && (1.0 / value).negative?
  else raise "unsupported corpus operation #{item["operation"]}"
  end
end

corpus_path = File.expand_path("../behavior/xna40-foundation-values.json", __dir__)
corpus = JSON.parse(File.read(corpus_path))
abort "behavior corpus is not PURE_XNA_DERIVED" unless corpus["category"] == "PURE_XNA_DERIVED"
failures = []
corpus.fetch("observations").each do |item|
  actual = execute(item)
  failures << {"id" => item["id"], "expected" => item["expected"], "actual" => actual} unless equivalent?(actual, item["expected"])
rescue Exception => error
  failures << {"id" => item["id"], "error" => "#{error.class}: #{error.message}"}
end

report = {
  "schemaVersion" => 1,
  "provenance" => corpus.fetch("provenance"),
  "OBSERVATIONS" => corpus.fetch("observations").length,
  "ASSERTIONS" => corpus.fetch("observations").length,
  "FAILURES" => failures.length,
  "groupCounts" => corpus.fetch("observations").group_by { |item| behavior_group(item) }.transform_values(&:length).sort.to_h,
  "failures" => failures
}
destination = File.expand_path("../docs/generated/behavior-corpus-report.json", __dir__)
File.write(destination, JSON.pretty_generate(report) + "\n")
puts "OBSERVATIONS=#{report["OBSERVATIONS"]}"
puts "ASSERTIONS=#{report["ASSERTIONS"]}"
puts "FAILURES=#{report["FAILURES"]}"
abort JSON.pretty_generate(failures) unless failures.empty?
