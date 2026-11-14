import Foundation
import GeoCore
import ToolSupport
import Tracks

extension ToolRunner {
    /// Reads a GPX file and says what is in it: the tracks with their length, time and whether each is an activity, the routes and
    /// the waypoints.
    ///
    /// - Parameter url: The GPX file.
    /// - Returns: The report.
    /// - Throws: ``ToolError`` if the file cannot be read as GPX.
    public static func trackInfo(url: URL) throws -> TrackInfoReport {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let file: GPXFile
        do { file = try GPXFile(contentsOf: url) } catch { throw ToolError("\(url.lastPathComponent): \(error.localizedDescription)") }
        var routesOfTracks: [Route] = []
        let tracks = file.tracks.map { track -> TrackInfoReport.TrackLine in
            let points = track.points
            let timed = points.isEmpty ? 0 : Double(points.filter { $0.time != nil }.count) / Double(points.count)
            let activity: Result<ActivityTrack, NotAnActivity>
            do { activity = .success(try track.activity()) } catch let reason as NotAnActivity { activity = .failure(reason) } catch {
                activity = .failure(.tooFewPoints(0))
            }
            do {
                let route = try track.route()
                routesOfTracks.append(route)
                return TrackInfoReport.TrackLine(
                    name: track.name, type: track.type, points: points.count, segments: track.segments.count, length: route.length,
                    box: route.boundingBox, timedFraction: timed, activity: activity, routeProblem: nil)
            } catch {
                return TrackInfoReport.TrackLine(
                    name: track.name, type: track.type, points: points.count, segments: track.segments.count, length: nil, box: nil,
                    timedFraction: timed, activity: activity, routeProblem: error.localizedDescription)
            }
        }
        let routes = file.routes.map { route -> TrackInfoReport.RouteLine in
            do {
                return TrackInfoReport.RouteLine(name: route.name, points: route.points.count, length: try route.route().length, routeProblem: nil)
            } catch {
                return TrackInfoReport.RouteLine(name: route.name, points: route.points.count, length: nil, routeProblem: error.localizedDescription)
            }
        }
        let near = file.waypoints.filter { waypoint in
            routesOfTracks.contains { $0.project(waypoint.point.coordinate).distance <= 100 }
        }.count
        return TrackInfoReport(
            fileName: url.lastPathComponent, fileSize: Int64(size), creator: file.creator, name: file.name, tracks: tracks, routes: routes,
            waypoints: file.waypoints.count, waypointsNearATrack: near)
    }
}
