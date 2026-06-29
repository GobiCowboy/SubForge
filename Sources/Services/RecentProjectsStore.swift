import Foundation

enum RecentProjectsStore {
    private static let key = "subforge.recent-projects.v2"

    static func load() -> [RecentProject] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let projects = try? JSONDecoder().decode([RecentProject].self, from: data)
        else {
            return []
        }
        return projects
    }

    static func save(_ projects: [RecentProject]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
