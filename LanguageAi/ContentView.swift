import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "swift")
                .imageScale(.large)
                .foregroundStyle(.orange)
            Text("LanguageAi")
                .font(.largeTitle)
                .bold()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
