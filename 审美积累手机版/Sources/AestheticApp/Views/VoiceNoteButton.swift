import SwiftUI

/// 语音输入按钮（把语音转文字写入绑定的备注）
struct VoiceNoteButton: View {
    @Binding var note: String
    @StateObject private var speech = SpeechRecognizer()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if speech.isRecording { speech.stop() } else { speech.start() }
            } label: {
                Label(speech.isRecording ? "停止" : "语音输入",
                      systemImage: speech.isRecording ? "stop.fill" : "mic.fill")
            }
            .buttonStyle(.bordered)

            if speech.isRecording {
                Text("正在听…").font(.caption).foregroundColor(AppTheme.secondaryText)
            }
            if !speech.transcript.isEmpty {
                Text("识别：\(speech.transcript)")
                    .font(.caption)
                    .foregroundColor(AppTheme.primarySoft)
                Button("采用这段语音") {
                    if note.isEmpty { note = speech.transcript } else { note += " " + speech.transcript }
                }
                .font(.caption)
            }
            if let errorMessage = speech.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(AppTheme.danger)
            }
        }
    }
}
