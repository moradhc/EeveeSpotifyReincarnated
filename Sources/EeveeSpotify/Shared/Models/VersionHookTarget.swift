enum VersionHookTarget {
    case v90 // Pre-9.1 builds (was ".latest")
    case lastAvailableiOS15
    case v91 // Spotify 9.1.x and later (9.2+, 10.x, …)
    case lastAvailableiOS14
}
