import UIKit
import Orion

struct HookTargetNameHelper {
    static var lyricsScrollProvider: String {
        switch EeveeSpotify.hookTarget {
        case .lastAvailableiOS14:
            return "Lyrics_CoreImpl.ScrollProvider"
        case .v91:
            // 9.2.0 moved the provider to Lyrics_NPVCommunicatorImpl; fall back to the
            // 9.1.x name when the new class isn't registered yet.
            if NSClassFromString("Lyrics_NPVCommunicatorImpl.LyricsScrollProviderPlugin") != nil {
                return "Lyrics_NPVCommunicatorImpl.LyricsScrollProviderPlugin"
            }
            return "Lyrics_CoreImpl.ScrollProvider"
        case .v90, .lastAvailableiOS15:
            return "Lyrics_NPVCommunicatorImpl.ScrollProvider"
        }
    }
}
