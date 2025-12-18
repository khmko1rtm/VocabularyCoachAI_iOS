import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ViewModel()
    @State private var showSettings = false
    @State private var showCopiedAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Input")) {
                    TextField("Word", text: $vm.word)
                        .autocapitalization(.none)
                    TextField("Student sentence", text: $vm.studentSentence)
                        .autocapitalization(.sentences)
                }

                Section(header: Text("Options")) {
                    Toggle(isOn: $vm.useExternalAPI) {
                        Text("Use external dictionary (demo)")
                    }
                    HStack {
                        Spacer()
                        Button("Settings") {
                            showSettings = true
                        }
                        Spacer()
                    }
                }

                Section {
                    Button(action: {
                        vm.generateJSON()
                        hideKeyboard()
                    }) {
                        if vm.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Generate JSON")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                Section(header: Text("Output JSON")) {
                    TextEditor(text: $vm.outputJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 240)

                    HStack {
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = vm.outputJSON
                            showCopiedAlert = true
                        }) {
                            Text("Copy JSON")
                        }
                        .alert(isPresented: $showCopiedAlert) {
                            Alert(title: Text("Copied"), message: Text("JSON copied to clipboard"), dismissButton: .default(Text("OK")))
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("AI Vocabulary Coach")
            .onAppear {
                vm.generateJSON()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(vm: vm)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vm: ViewModel
    @Environment(\.presentationMode) var presentation

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("External API key (demo)")) {
                    TextField("API Key", text: $vm.apiKeyInput)
                        .autocapitalization(.none)
                    Text("This demo stores the key in Keychain and shows how it can be used in real-world integration with dictionary APIs such as Oxford and Wordnik")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("Save API Key") {
                        vm.saveAPIKeyToKeychain()
                        vm.useExternalAPI = true
                        presentation.wrappedValue.dismiss()
                    }
                    Button("Clear API Key") {
                        vm.clearAPIKey()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
