import SwiftUI

/// Hosts the Task 2.13 end-to-end inbound demo for now. In follow-up
/// tasks this will graduate into proper audio-routing / ducking
/// settings, with the demo controls split out as needed.
struct AudioTab: View {
    let hudViewModel: HUDViewModel

    var body: some View {
        InboundDemoView(hudViewModel: hudViewModel)
            .padding(8)
    }
}
