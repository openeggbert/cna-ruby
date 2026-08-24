# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

EXPECTED_SHA256 = "398d0201af0e3c719c152f8659a871cb59710a7dfafc079df6694d453c737855"
SUPPORTED_IDS = %w[
  math.clamp.low math.lerp math.barycentric math.catmullrom math.hermite math.smoothstep
  math.wrapangle math.to_degrees vector2.add vector2.dot vector2.normalize vector2.reflect
  vector2.barycentric vector2.transform vector2.zero.copy
  vector3.cross vector3.distance vector3.reflect vector3.transform_normal vector3.smoothstep
  vector4.dot vector4.hermite vector4.transform
  quaternion.identity quaternion.yaw quaternion.concatenate.identity quaternion.slerp quaternion.from_matrix.identity
  matrix.translation matrix.multiply matrix.inverse.product matrix.inverse.singular matrix.rotation.y
  matrix.perspective.infinity matrix.decompose matrix.billboard matrix.orthographic
  color.clamp color.packed color.lerp color.multiply
  rectangle.contains.inclusive_min rectangle.contains.exclusive_max rectangle.intersect
  rectangle.union rectangle.inflate rectangle.offset point.value_equality point.zero.copy
  plane.normalize plane.dot.coordinate plane.box.back plane.sphere.tangent
  ray.box ray.sphere.tangent ray.plane.behind
  box.contains.point.edge box.contains.sphere box.merge
  sphere.contains.point.surface sphere.merge sphere.transform
  frustum.contains.point frustum.disjoint.point frustum.contains.box frustum.disjoint.sphere
  frustum.ray.entry frustum.corners
  vector2.normalize.zero.bits vector3.normalize.zero.bits vector4.normalize.zero.bits
  vector.scalar.divide.bits quaternion.zero.nonfinite.bits quaternion.products.bits
  matrix.vector.transforms.bits plane.transform.bits value.nan.equality value.hash.codes
  mathhelper.edge.bits vector3.edge.bits quaternion.edge.bits matrix.edge.bits matrix.degenerate.bits
  plane.edge.bits geometry.nonfinite.tangent frustum.planes.corners.bits frustum.gjk.relations.bits
  float32.signed_zero
].freeze

source = ARGV.fetch(0) { abort "usage: import_behavior_corpus.rb PATH" }
bytes = File.binread(source)
abort "behavior source SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == EXPECTED_SHA256
source_corpus = JSON.parse(bytes)
observations = source_corpus.fetch("observations").select { |item| SUPPORTED_IDS.include?(item.fetch("id")) }
abort "behavior selection mismatch" unless observations.length == SUPPORTED_IDS.length
milestone_path = File.expand_path("../behavior/xna40-color-rectangle-values.json", __dir__)
milestone = JSON.parse(File.read(milestone_path))
abort "Milestone 3 behavior evidence is not PURE_XNA_DERIVED" unless milestone["category"] == "PURE_XNA_DERIVED"
observations.concat(milestone.fetch("observations"))
curve_path = File.expand_path("../behavior/xna40-curve-values.json", __dir__)
curve = JSON.parse(File.read(curve_path))
abort "Milestone 4 behavior evidence is not PURE_XNA_DERIVED" unless curve["category"] == "PURE_XNA_DERIVED"
observations.concat(curve.fetch("observations"))
packed_vector_path = File.expand_path("../behavior/xna40-packed-vector-values.json", __dir__)
packed_vector = JSON.parse(File.read(packed_vector_path))
abort "Milestone 5 behavior evidence is not PURE_XNA_DERIVED" unless packed_vector["category"] == "PURE_XNA_DERIVED"
observations.concat(packed_vector.fetch("observations"))
foundation_path = File.expand_path("../behavior/xna40-foundation-values.json", __dir__)
previous_foundation = JSON.parse(File.read(foundation_path))
mouse_observations = previous_foundation.fetch("observations").select do |item|
  item.fetch("id").start_with?("button_state.", "mouse_state.")
end
abort "Milestone 6 Mouse behavior selection mismatch" unless mouse_observations.length == 15
observations.concat(mouse_observations)
gamepad_path = File.expand_path("../behavior/xna40-gamepad-values.json", __dir__)
gamepad = JSON.parse(File.read(gamepad_path))
abort "Milestone 7 behavior evidence is not PURE_XNA_DERIVED" unless gamepad["category"] == "PURE_XNA_DERIVED"
observations.concat(gamepad.fetch("observations"))
vertex_element_path = File.expand_path("../behavior/xna40-vertex-element-values.json", __dir__)
vertex_element = JSON.parse(File.read(vertex_element_path))
abort "Milestone 8 VertexElement behavior evidence is not PURE_XNA_DERIVED" unless vertex_element["category"] == "PURE_XNA_DERIVED"
observations.concat(vertex_element.fetch("observations"))
display_orientation_path = File.expand_path("../behavior/xna40-display-orientation-values.json", __dir__)
display_orientation = JSON.parse(File.read(display_orientation_path))
unless display_orientation["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 9 DisplayOrientation evidence lacks observation-level provenance"
end
observations.concat(display_orientation.fetch("observations"))
graphics_device_status_path = File.expand_path("../behavior/xna40-graphics-device-status-values.json", __dir__)
graphics_device_status = JSON.parse(File.read(graphics_device_status_path))
unless graphics_device_status["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 10 GraphicsDeviceStatus evidence lacks observation-level provenance"
end
observations.concat(graphics_device_status.fetch("observations"))
graphics_profile_path = File.expand_path("../behavior/xna40-graphics-profile-values.json", __dir__)
graphics_profile = JSON.parse(File.read(graphics_profile_path))
unless graphics_profile["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 11 GraphicsProfile evidence lacks observation-level provenance"
end
observations.concat(graphics_profile.fetch("observations"))
abort "duplicate behavior observation id" unless observations.map { |item| item.fetch("id") }.uniq.length == observations.length
result = source_corpus.merge(
  "provenance" => "Observation-level provenance: legacy entries default to PURE_XNA_DERIVED; DisplayOrientation, GraphicsDeviceStatus, and GraphicsProfile separate XNA metadata facts from RUBY_MAPPING_QUALIFICATION; never CNA output",
  "category" => "MIXED_WITH_OBSERVATION_PROVENANCE",
  "sourceSha256" => EXPECTED_SHA256,
  "milestone3SourceAssemblySha256" => milestone.fetch("sourceAssemblySha256"),
  "milestone4SourceAssemblySha256" => curve.fetch("sourceAssemblySha256"),
  "milestone5SourceAssemblySha256" => packed_vector.fetch("sourceAssemblySha256"),
  "milestone6SourceAssemblySha256" => previous_foundation.fetch("milestone6SourceAssemblySha256"),
  "milestone7SourceAssemblySha256" => gamepad.fetch("sourceAssemblySha256"),
  "milestone8SourceAssemblySha256" => vertex_element.fetch("sourceAssemblySha256"),
  "milestone9SourceAssemblySha256" => display_orientation.fetch("sourceAssemblySha256"),
  "milestone10SourceAssemblySha256" => graphics_device_status.fetch("sourceAssemblySha256"),
  "milestone11SourceAssemblySha256" => graphics_profile.fetch("sourceAssemblySha256"),
  "observations" => observations
)
destination = File.expand_path("../behavior/xna40-foundation-values.json", __dir__)
FileUtils.mkdir_p(File.dirname(destination))
File.write(destination, JSON.pretty_generate(result) + "\n")
puts "OBSERVATIONS=#{observations.length}"
