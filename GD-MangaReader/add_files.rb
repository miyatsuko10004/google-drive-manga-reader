require 'xcodeproj'

project_path = "GD-MangaReader.xcodeproj"
project = Xcodeproj::Project.open(project_path)

files_to_add = [
  "GD-MangaReader/Views/RecentComicsShelfView.swift",
  "GD-MangaReader/Views/DriveItemGridView.swift",
  "GD-MangaReader/Views/DriveItemListView.swift"
]

target = project.targets.first
group = project.main_group.find_subpath("GD-MangaReader/Views", true)

files_to_add.each do |file_path|
  file_ref = group.new_reference(File.basename(file_path))
  target.add_file_references([file_ref])
end

project.save
puts "Added files successfully."
