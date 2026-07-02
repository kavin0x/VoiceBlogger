import AppIntents
import SwiftUI
import WidgetKit

struct StartRecordingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.voiceblogger.control.start-recording") {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Start Recording", systemImage: "mic.fill")
            }
        }
        .displayName("Start Recording")
        .description("Open VoiceBlogger and start a new recording.")
    }
}

struct StopRecordingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.voiceblogger.control.stop-recording") {
            ControlWidgetButton(action: StopRecordingIntent()) {
                Label("Stop Recording", systemImage: "stop.fill")
            }
        }
        .displayName("Stop Recording")
        .description("Stop the current recording in VoiceBlogger.")
    }
}
