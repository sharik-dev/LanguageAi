import SwiftUI
import Speech
import AVFoundation

private let backendURLs = [
    URL(string: "http://127.0.0.1:3010/api/assistant")!,
    URL(string: "http://51.91.125.99:3010/api/assistant")!
]

struct ContentView: View {
    @StateObject private var assistant = AssistantViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.10), Color(red: 0.11, green: 0.14, blue: 0.17)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    header
                    conversation
                    commandBar
                }
                .padding()
            }
            .navigationTitle("Jarvis")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await assistant.requestSpeechPermission()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(assistant.isRecording ? .red.opacity(0.25) : .cyan.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: assistant.isRecording ? "waveform.circle.fill" : "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(assistant.isRecording ? .red : .cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(assistant.status)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(assistant.partialTranscript.isEmpty ? "Parle naturellement, Jarvis execute ou affiche ce qui est utile." : assistant.partialTranscript)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(assistant.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: assistant.messages.count) {
                guard let last = assistant.messages.last else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var commandBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Demande a Jarvis...", text: $assistant.typedMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    Task { await assistant.sendTypedMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(assistant.typedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.isLoading)
            }

            Button {
                Task { await assistant.toggleRecording() }
            } label: {
                Label(assistant.isRecording ? "Arreter l'ecoute" : "Parler", systemImage: assistant.isRecording ? "stop.fill" : "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(assistant.isRecording ? .red : .cyan)
            .disabled(!assistant.canRecord || assistant.isLoading)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            Text(message.text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(12)
                .background(message.role == .user ? .blue.opacity(0.82) : .white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ForEach(message.actions) { action in
                ActionView(action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct ActionView: View {
    let action: AssistantAction

    var body: some View {
        switch action.type {
        case "display_image":
            VStack(alignment: .leading, spacing: 8) {
                if let imageURL = action.imageURL.flatMap(URL.init(string:)) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 220)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }

                if let title = action.title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .padding(10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 420)
        default:
            EmptyView()
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.24))
                .frame(height: 220)
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                Text(action.query ?? "Image")
                    .font(.headline)
            }
            .foregroundStyle(.white.opacity(0.74))
        }
    }
}

@MainActor
final class AssistantViewModel: NSObject, ObservableObject {
    @Published var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "Pret. Tu peux me demander de repondre, d'agir, ou d'afficher une image.")
    ]
    @Published var typedMessage = ""
    @Published var partialTranscript = ""
    @Published var isRecording = false
    @Published var isLoading = false
    @Published var canRecord = false
    @Published var status = "Assistant local"

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let speaker = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestSpeechPermission() async {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        canRecord = speechGranted && micGranted
        status = canRecord ? "Assistant local" : "Micro ou dictee non autorise"
    }

    func toggleRecording() async {
        isRecording ? await stopRecordingAndSend() : startRecording()
    }

    func sendTypedMessage() async {
        let text = typedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedMessage = ""
        await send(text)
    }

    private func startRecording() {
        guard canRecord, !audioEngine.isRunning else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        partialTranscript = ""

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            status = "J'ecoute"

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.partialTranscript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        await self.stopRecordingAndSend()
                    }
                }
            }
        } catch {
            status = "Impossible de demarrer le micro"
            stopAudio()
        }
    }

    private func stopRecordingAndSend() async {
        let finalText = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopAudio()
        guard !finalText.isEmpty else { return }
        await send(finalText)
    }

    private func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        status = "Assistant local"
    }

    private func send(_ text: String) async {
        messages.append(ChatMessage(role: .user, text: text))
        isLoading = true
        status = "Codex reflechit"

        do {
            let assistantResponse = try await postToBackend(message: text)
            let reply = ChatMessage(role: .assistant, text: assistantResponse.message, actions: assistantResponse.actions)
            messages.append(reply)
            speak(assistantResponse.speak ?? assistantResponse.message)
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "Je n'arrive pas a joindre le backend. Essaie http://51.91.125.99:3010/health dans Safari. Erreur: \(error.localizedDescription)"))
        }

        isLoading = false
        status = "Assistant local"
    }

    private func postToBackend(message: String) async throws -> AssistantResponse {
        let body = try JSONEncoder().encode(AssistantRequest(message: message))
        var lastError: Error?

        for url in backendURLs {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 180
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                    throw URLError(.badServerResponse)
                }

                return try JSONDecoder().decode(AssistantResponse.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.48
        speaker.speak(utterance)
    }
}

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    var actions: [AssistantAction] = []
}

struct AssistantRequest: Encodable {
    let message: String
}

struct AssistantResponse: Decodable {
    let message: String
    let speak: String?
    let actions: [AssistantAction]
}

struct AssistantAction: Decodable, Identifiable {
    let id = UUID()
    let type: String
    let title: String?
    let query: String?
    let imageURL: String?

    enum CodingKeys: String, CodingKey {
        case type
        case title
        case query
        case imageURL = "image_url"
    }
}

#Preview {
    ContentView()
}
