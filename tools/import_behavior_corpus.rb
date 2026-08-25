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
viewport_path = File.expand_path("../behavior/xna40-viewport-values.json", __dir__)
viewport = JSON.parse(File.read(viewport_path))
unless viewport["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 12 Viewport evidence lacks observation-level provenance"
end
observations.concat(viewport.fetch("observations"))
clear_options_path = File.expand_path("../behavior/xna40-clear-options-values.json", __dir__)
clear_options = JSON.parse(File.read(clear_options_path))
unless clear_options["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 13 ClearOptions evidence lacks observation-level provenance"
end
observations.concat(clear_options.fetch("observations"))
depth_format_path = File.expand_path("../behavior/xna40-depth-format-values.json", __dir__)
depth_format = JSON.parse(File.read(depth_format_path))
unless depth_format["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 14 DepthFormat evidence lacks observation-level provenance"
end
observations.concat(depth_format.fetch("observations"))
primitive_type_path = File.expand_path("../behavior/xna40-primitive-type-values.json", __dir__)
primitive_type = JSON.parse(File.read(primitive_type_path))
unless primitive_type["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 15 PrimitiveType evidence lacks observation-level provenance"
end
observations.concat(primitive_type.fetch("observations"))
batch_path = File.expand_path("../behavior/xna40-pure-managed-enum-batch-values.json", __dir__)
batch = JSON.parse(File.read(batch_path))
unless batch["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 16 pure managed enum batch evidence lacks observation-level provenance"
end
observations.concat(batch.fetch("observations"))
touch_path = File.expand_path("../behavior/xna40-touch-closure-values.json", __dir__)
touch = JSON.parse(File.read(touch_path))
unless touch["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 17 Input.Touch closure evidence lacks observation-level provenance"
end
observations.concat(touch.fetch("observations"))
interfaces_path = File.expand_path("../behavior/xna40-interface-contract-values.json", __dir__)
interfaces = JSON.parse(File.read(interfaces_path))
unless interfaces["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 18 interface contract evidence lacks observation-level provenance"
end
observations.concat(interfaces.fetch("observations"))
events_path = File.expand_path("../behavior/xna40-event-projection-values.json", __dir__)
events = JSON.parse(File.read(events_path))
unless events["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 20 event projection evidence lacks observation-level provenance"
end
observations.concat(events.fetch("observations"))
bcl_path = File.expand_path("../behavior/xna40-bcl-projection-values.json", __dir__)
bcl = JSON.parse(File.read(bcl_path))
unless bcl["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 21 BCL projection evidence lacks observation-level provenance"
end
observations.concat(bcl.fetch("observations"))
exception_path = File.expand_path("../behavior/xna40-xna-exception-values.json", __dir__)
exceptions = JSON.parse(File.read(exception_path))
unless exceptions["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 22 XNA exception evidence lacks observation-level provenance"
end
observations.concat(exceptions.fetch("observations"))
touch_value_path = File.expand_path("../behavior/xna40-touch-value-values.json", __dir__)
touch_values = JSON.parse(File.read(touch_value_path))
unless touch_values["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 23 Input.Touch value evidence lacks observation-level provenance"
end
observations.concat(touch_values.fetch("observations"))
descriptor_path = File.expand_path("../behavior/xna40-managed-descriptor-values.json", __dir__)
descriptors = JSON.parse(File.read(descriptor_path))
unless descriptors["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 24 managed descriptor evidence lacks observation-level provenance"
end
observations.concat(descriptors.fetch("observations"))
free_path = File.expand_path("../behavior/xna40-constructor-free-values.json", __dir__)
constructor_free = JSON.parse(File.read(free_path))
unless constructor_free["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 25 constructor-free evidence lacks observation-level provenance"
end
observations.concat(constructor_free.fetch("observations"))
collection_path = File.expand_path("../behavior/xna40-display-mode-collection-values.json", __dir__)
display_modes = JSON.parse(File.read(collection_path))
unless display_modes["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 26 DisplayModeCollection evidence lacks observation-level provenance"
end
observations.concat(display_modes.fetch("observations"))
attribute_path = File.expand_path("../behavior/xna40-content-attribute-values.json", __dir__)
content_attributes = JSON.parse(File.read(attribute_path))
unless content_attributes["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 27 ContentSerializer attribute evidence lacks observation-level provenance"
end
observations.concat(content_attributes.fetch("observations"))
touch_collection_path = File.expand_path("../behavior/xna40-touch-collection-values.json", __dir__)
touch_collection = JSON.parse(File.read(touch_collection_path))
unless touch_collection["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 31 TouchCollection evidence lacks observation-level provenance"
end
observations.concat(touch_collection.fetch("observations"))
touch_panel_path = File.expand_path("../behavior/xna40-touch-panel-values.json", __dir__)
touch_panel = JSON.parse(File.read(touch_panel_path))
unless touch_panel["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 32 TouchPanel evidence lacks observation-level provenance"
end
observations.concat(touch_panel.fetch("observations"))
services_path = File.expand_path("../behavior/xna40-game-service-container-values.json", __dir__)
game_services = JSON.parse(File.read(services_path))
unless game_services["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 33 GameServiceContainer evidence lacks observation-level provenance"
end
observations.concat(game_services.fetch("observations"))
game_components_path = File.expand_path("../behavior/xna40-game-component-collection-values.json", __dir__)
game_component_collection = JSON.parse(File.read(game_components_path))
unless game_component_collection["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 35 GameComponentCollection evidence lacks observation-level provenance"
end
observations.concat(game_component_collection.fetch("observations"))
disposable_path = File.expand_path("../behavior/xna40-disposable-collapse-values.json", __dir__)
disposable = JSON.parse(File.read(disposable_path))
unless disposable["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 36 IDisposable collapse evidence lacks observation-level provenance"
end
observations.concat(disposable.fetch("observations"))
game_components_state_path = File.expand_path("../behavior/xna40-game-components-values.json", __dir__)
game_components = JSON.parse(File.read(game_components_state_path))
unless game_components["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 37 Game component engine evidence lacks observation-level provenance"
end
observations.concat(game_components.fetch("observations"))
game_component_path = File.expand_path("../behavior/xna40-game-component-values.json", __dir__)
game_component = JSON.parse(File.read(game_component_path))
unless game_component["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 38 GameComponent evidence lacks observation-level provenance"
end
observations.concat(game_component.fetch("observations"))
member_edges_path = File.expand_path("../behavior/xna40-member-level-dependency-values.json", __dir__)
member_edges = JSON.parse(File.read(member_edges_path))
unless member_edges["category"] == "MIXED_WITH_OBSERVATION_PROVENANCE"
  abort "Milestone 39 member-level dependency evidence lacks observation-level provenance"
end
observations.concat(member_edges.fetch("observations"))
abort "duplicate behavior observation id" unless observations.map { |item| item.fetch("id") }.uniq.length == observations.length
result = source_corpus.merge(
  "provenance" => "Observation-level provenance: legacy entries default to PURE_XNA_DERIVED; DisplayOrientation, GraphicsDeviceStatus, GraphicsProfile, Viewport, ClearOptions, DepthFormat, PrimitiveType, the Foundation 16 pure managed enum batch, the Foundation 17 Input.Touch closure, the Foundation 18 interface contracts, the Foundation 20 event projection, the Foundation 21 BCL projection, the Foundation 22 XNA exception cluster, the Foundation 23 Input.Touch value types, the Foundation 24 managed descriptors, the Foundation 25 constructor-free classes, the Foundation 26 DisplayModeCollection, the Foundation 27 ContentSerializer attributes, the Foundation 31 TouchCollection pair, the Foundation 32 TouchPanel, the Foundation 33 GameServiceContainer, the Foundation 35 GameComponentCollection, the Foundation 36 IDisposable collapse, the Foundation 37 Game component engine, the Foundation 38 GameComponent, and the Foundation 39 member-level dependency edges separate XNA facts from RUBY_MAPPING_QUALIFICATION; never CNA output",
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
  "milestone12SourceAssemblySha256" => viewport.fetch("sourceAssemblySha256"),
  "milestone13SourceAssemblySha256" => clear_options.fetch("sourceAssemblySha256"),
  "milestone14SourceAssemblySha256" => depth_format.fetch("sourceAssemblySha256"),
  "milestone15SourceAssemblySha256" => primitive_type.fetch("sourceAssemblySha256"),
  "milestone16SourceAssemblySha256" => batch.fetch("sourceAssemblySha256"),
  "milestone17SourceAssemblySha256" => touch.fetch("sourceAssemblySha256"),
  "milestone18SourceAssemblySha256" => interfaces.fetch("sourceAssemblySha256"),
  "milestone20SourceAssemblySha256" => events.fetch("sourceAssemblySha256"),
  "milestone21SourceAssemblySha256" => bcl.fetch("sourceAssemblySha256"),
  "milestone22SourceAssemblySha256" => exceptions.fetch("sourceAssemblySha256"),
  "milestone22SourceGraphicsAssemblySha256" => exceptions.fetch("sourceGraphicsAssemblySha256"),
  "milestone23SourceAssemblySha256" => touch_values.fetch("sourceAssemblySha256"),
  "milestone24SourceAssemblySha256" => descriptors.fetch("sourceAssemblySha256"),
  "milestone24SourceGameAssemblySha256" => descriptors.fetch("sourceGameAssemblySha256"),
  "milestone25SourceAssemblySha256" => constructor_free.fetch("sourceAssemblySha256"),
  "milestone26SourceAssemblySha256" => display_modes.fetch("sourceAssemblySha256"),
  "milestone27SourceAssemblySha256" => content_attributes.fetch("sourceAssemblySha256"),
  "milestone31SourceAssemblySha256" => touch_collection.fetch("sourceAssemblySha256"),
  "milestone32SourceAssemblySha256" => touch_panel.fetch("sourceAssemblySha256"),
  "milestone33SourceAssemblySha256" => game_services.fetch("sourceAssemblySha256"),
  "milestone35SourceAssemblySha256" => game_component_collection.fetch("sourceAssemblySha256"),
  "milestone36SourceAssemblySha256" => disposable.fetch("sourceAssemblySha256"),
  "milestone37SourceAssemblySha256" => game_components.fetch("sourceAssemblySha256"),
  "milestone38SourceAssemblySha256" => game_component.fetch("sourceAssemblySha256"),
  "milestone39SourceAssemblySha256" => member_edges.fetch("sourceAssemblySha256"),
  # Foundation 16 was merged by documented deterministic replay because this reconstructed host
  # does not carry the upstream source. Re-running this importer with the real source restores the
  # same observation set; it must not be run against any other artifact.
  "milestone16MergeMethod" => "deterministic replay; upstream source #{EXPECTED_SHA256} is absent from this reconstructed host, so import_behavior_corpus.rb was not run; byte-preserving serialisation of the pre-merge corpus was proved before appending",
  "milestone20MergeMethod" => "deterministic replay; upstream source #{EXPECTED_SHA256} is still absent, so import_behavior_corpus.rb was not run; byte-preserving serialisation of the pre-merge corpus (SHA-256 fc87b85cebf2c09de2b0a2ca33051d466f16c87ed57119165ba717c9ff2e3b21, 339 observations) was proved before appending 16 additive observations",
  "milestone21MergeMethod" => "deterministic replay; upstream source #{EXPECTED_SHA256} is still absent, so import_behavior_corpus.rb was not run; byte-preserving serialisation of the pre-merge corpus (SHA-256 fab5788ffbaa551b5f3ca6d4381c2c7a64a620810513ff796cad44ce805abb8f, 355 observations) was proved before appending 11 additive observations",
  "milestone31MergeMethod" => "deterministic replay; upstream source #{EXPECTED_SHA256} is still absent, so import_behavior_corpus.rb was not run; byte-preserving serialisation of the pre-merge corpus (SHA-256 b2db718e5813c457f93229b1297001a8fa4c4d17587af776261f03eb449b3853, 420 observations) was proved before appending 9 additive observations",
  "milestone32MergeMethod" => "deterministic replay; upstream source #{EXPECTED_SHA256} is still absent, so import_behavior_corpus.rb was not run; byte-preserving serialisation of the pre-merge corpus (SHA-256 e1050871516000c313b57e7610ea8a5c39f00d614696a9349923aa4886c2349f, 429 observations) was proved before appending 4 additive observations",
  "milestone33MergeMethod" => "deterministic replay; upstream source #{EXPECTED_SHA256} is still absent, so import_behavior_corpus.rb was not run; byte-preserving serialisation of the pre-merge corpus (SHA-256 166b4bfdbb5c1f97a579b620329b2973ccfcd9f59b72a7f40e8b387910b139df, 433 observations) was proved before appending 2 additive observations",
  "observations" => observations
)
destination = File.expand_path("../behavior/xna40-foundation-values.json", __dir__)
FileUtils.mkdir_p(File.dirname(destination))
formatted = JSON.pretty_generate(result).gsub(/\[\n\s*\]/, "[]")
# Preserve the established decimal spelling across Ruby JSON generator versions.
{
  "1.5259254737998596e-05" => "0.000015259254737998596",
  "4.577776421485031e-05" => "0.00004577776421485031",
  "-1.5259254737998596e-05" => "-0.000015259254737998596",
  "-4.577776421485031e-05" => "-0.00004577776421485031"
}.each { |current, retained| formatted.gsub!(current, retained) }
File.write(destination, formatted + "\n")
puts "OBSERVATIONS=#{observations.length}"
