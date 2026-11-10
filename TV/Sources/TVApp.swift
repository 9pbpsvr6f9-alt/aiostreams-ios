import AVFoundation
import SwiftUI

@main
struct AIOStreamsTVApp: App {
    @StateObject private var session = Session()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        AppLog.info("app", "started \(AppInfo.version) on \(AppInfo.deviceModel) tvOS \(UIDevice.current.systemVersion)")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.stage {
                case .needsServer: ServerView()
                case .needsSignIn: SignInView()
                case .signedIn: MainView()
                }
            }
            .environmentObject(session)
            .preferredColorScheme(.dark)
        }
    }
}

/// A message under a screen, for what went wrong.
struct ErrorText: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }
}

struct ServerView: View {
    @EnvironmentObject private var session: Session
    @State private var address = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 40) {
            Text("AIOStreams")
                .font(.system(size: 76, weight: .bold))
            Text("Enter your server's address from the configure page: Save & Install → Jellyfin apps → Connect. With a share alias it is short, like your-instance/jellyfin/u/alias.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1100)
            TextField("Server address", text: $address)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(maxWidth: 1100)
                .onSubmit(connect)
            Button(working ? "Connecting…" : "Connect", action: connect)
                .disabled(working || address.trimmingCharacters(in: .whitespaces).isEmpty)
            ErrorText(text: error)
        }
        .padding(80)
    }

    private func connect() {
        guard !working else { return }
        working = true
        error = nil
        Task {
            do {
                try await session.connect(to: address)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var session: Session
    @State private var users: [PublicUser] = []
    @State private var quickConnect = false
    @State private var code: String?
    @State private var pickedUser: String?
    @State private var name = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var poll: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 48) {
                Text(session.serverName ?? "Sign in")
                    .font(.system(size: 60, weight: .bold))

                if quickConnect {
                    VStack(spacing: 20) {
                        Text("Quick Connect").font(.title2)
                        if let code {
                            Text(code)
                                .font(.system(size: 120, weight: .heavy, design: .monospaced))
                            Text("On the configure page, open Save & Install → Jellyfin apps → Connect and type this code into the Quick Connect box, then approve it.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 1100)
                            ProgressView()
                        } else {
                            ProgressView()
                        }
                    }
                }

                if !users.isEmpty {
                    VStack(spacing: 16) {
                        Text("Who's watching?").font(.title3).foregroundStyle(.secondary)
                        HStack(spacing: 30) {
                            ForEach(users) { user in
                                Button(user.name ?? "User") {
                                    name = user.name ?? ""
                                    pickedUser = user.id
                                    if user.hasPassword == false { signIn() }
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 24) {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password (and /PIN if the user has one)", text: $password)
                        .onSubmit(signIn)
                    Button(working ? "Signing in…" : "Sign in", action: signIn)
                        .disabled(working || name.isEmpty)
                }
                .frame(maxWidth: 1000)

                ErrorText(text: error)

                Button("Use a different server", role: .destructive) { session.forgetServer() }
                    .font(.callout)
            }
            .padding(80)
        }
        .task { await load() }
        .onDisappear { poll?.cancel() }
    }

    private func load() async {
        guard let client = session.client else { return }
        // A picker address lists its users, as a Jellyfin server does.
        users = (try? await client.get("/Users/Public") as [PublicUser]) ?? []
        let enabled = (try? await client.get("/QuickConnect/Enabled") as Bool) ?? false
        if enabled { startQuickConnect() }
    }

    private func startQuickConnect() {
        guard let client = session.client else { return }
        quickConnect = true
        poll?.cancel()
        poll = Task {
            do {
                let started: QuickConnectState = try await client.post("/QuickConnect/Initiate")
                code = started.code
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(4))
                    let state: QuickConnectState = try await client.get("/QuickConnect/Connect", ["Secret": started.secret])
                    if state.authenticated == true {
                        let result: AuthResult = try await client.post(
                            "/Users/AuthenticateWithQuickConnect",
                            body: ["Secret": started.secret]
                        )
                        session.signIn(result)
                        return
                    }
                }
            } catch is CancellationError {
            } catch {
                // A code lasts a few minutes; a new one replaces it.
                if !Task.isCancelled {
                    AppLog.info("signin", "quick connect: \(error.localizedDescription)")
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { startQuickConnect() }
                }
            }
        }
    }

    private func signIn() {
        guard let client = session.client, !working, !name.isEmpty else { return }
        working = true
        error = nil
        Task {
            do {
                let result: AuthResult = try await client.post(
                    "/Users/AuthenticateByName",
                    body: ["Username": name, "Pw": password]
                )
                poll?.cancel()
                session.signIn(result)
            } catch let failure as JellyfinError where failure.status == 401 {
                error = "That name and password don't match."
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
