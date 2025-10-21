import AresKit

extension Ares {
    final class Surface: Sendable {
        private let surface: ares_surface_t

        var unsafeCValue: ares_surface_t {
            surface
        }

        init(cSurface: ares_surface_t) {
            self.surface = cSurface
        }

        deinit {
            let surface = self.surface
            Task.detached { @MainActor in
                ares_surface_free(surface)
            }
        }
    }
}
