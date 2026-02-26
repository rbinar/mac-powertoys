require 'xcodeproj'

project_path = 'MacPowerToys.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.first

# Find the Features group
features_group = project.main_group.find_subpath(File.join('MacPowerToys', 'Features'), true)

# Create ZoomIt group
zoomit_group = features_group.new_group('ZoomIt')

# Add files
files = [
  'MacPowerToys/Features/ZoomIt/ZoomItModel.swift',
  'MacPowerToys/Features/ZoomIt/ZoomItOverlayView.swift',
  'MacPowerToys/Features/ZoomIt/ZoomItView.swift'
]

files.each do |file_path|
  file_ref = zoomit_group.new_reference(File.basename(file_path))
  target.add_file_references([file_ref])
end

project.save
puts "Successfully added ZoomIt files to Xcode project."
