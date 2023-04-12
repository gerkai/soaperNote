//
//  ContentView.swift
//  test3
//
//  Created by Geng Szoa on 4/6/23.
//

import SwiftUI
import AVFoundation

func setupAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowAirPlay])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
        print("Failed to set up audio session: \(error)")
    }
}

struct SoundMeterView: View {
    let numberOfSegments: Int
    let currentValue: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<numberOfSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(self.segmentColor(for: index))
                    .frame(width: self.segmentWidth(), height: 20)
            }
        }
    }

    private func segmentWidth() -> CGFloat {
        return (UIScreen.main.bounds.width * 0.8 - CGFloat(numberOfSegments - 1) * 2) / CGFloat(numberOfSegments)
    }

    private func segmentColor(for index: Int) -> Color {
        let step = 0.4 / CGFloat(numberOfSegments)
        let threshold = pow(step * CGFloat(index + 1), 0.1)

        if currentValue >= threshold {
            return Color.green
        } else {
            return Color.gray
        }
    }

}


struct RecordView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var transcribeEnabled: Bool
    
    var body: some View {
        VStack {
            if audioRecorder.isRecording {
                Text("Recording...")
            } else {
                Text("Click to Record")
            }
            
            Button(action: {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording(shouldTranscribe: true)
                    self.transcribeEnabled = false
                } else {
                    audioRecorder.startRecording()
                }
            }) {
                Image(systemName: audioRecorder.isRecording ? "stop.circle" : "mic.circle")
                    .font(.system(size: 70))
                    .foregroundColor(audioRecorder.isRecording ? .red : .green)
            }
            
            ScrollView {
                ScrollViewReader { scrollViewProxy in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(audioRecorder.transcription.components(separatedBy: "\n").indices, id: \.self) { index in
                            Text(audioRecorder.transcription.components(separatedBy: "\n")[index])
                                .id(index)
                        }
                    }
                    .onChange(of: audioRecorder.transcription) { _ in
                        DispatchQueue.main.async {
                            withAnimation {
                                let lastIndex = audioRecorder.transcription.components(separatedBy: "\n").count - 1
                                scrollViewProxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(width: 300, height: 250)
            .background(Color(.systemGroupedBackground))
            .cornerRadius(10)
            .padding()
        }
        .frame(width: 300, height: 400)
    }
}







struct PlaybackView: View {
    @ObservedObject var audioRecorder: AudioRecorder

    var body: some View {
        HStack {
            if audioRecorder.isPlaying {
                Text("Playing...")
            } else {
                Text("Play Recording")
            }
            Button(action: {
                if audioRecorder.isPlaying {
                    audioRecorder.stopPlaying()
                } else {
                    audioRecorder.playRecording()
                }
            }) {
                Image(systemName: audioRecorder.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(audioRecorder.isPlaying ? .red : .green)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct RoundedButton: View {
    @Binding var scanResult: String
    @Binding var isButtonEnabled: Bool
   
    
    var body: some View {
        Button(action: {
            presentScanner()
        }, label: {
            Image(systemName: "qrcode.viewfinder")
                .foregroundColor(.white)
                .padding(15)
                .background(Color.blue)
                .clipShape(Circle())
        })
        .padding()
        .disabled(!isButtonEnabled)
        .opacity(isButtonEnabled ? 1.0 : 0.5) // apply opacity to button
        .onAppear {
            isButtonEnabled = false
        }
    }
    
    private func presentScanner() {
        var scannerView = QRScanner(result: $scanResult)
        let scannerVC = UIHostingController(rootView: scannerView)

        // Set the onQRCodeDetected callback in the QRScanner instance
        scannerView.onQRCodeDetected = { [weak scannerVC] in
            scannerVC?.dismiss(animated: true, completion: nil)
           
        }

        UIApplication.shared.windows.first?.rootViewController?.present(scannerVC, animated: true, completion: nil)
    }
    

}


                
struct ContentView: View {
    @State private var fileURL: URL?
    @State private var model: String = "whisper-1"
    @State private var status: String = ""
    @State private var transcribeEnabled: Bool = true
    @State private var response: String = ""
    @State private var isButtonEnabled = true
    @State var scanResult = "No QR code detected"
   
    @StateObject private var audioRecorder = AudioRecorder()
    
    var body: some View {
        
        
        VStack {
            
            RecordView(audioRecorder:audioRecorder, transcribeEnabled: $transcribeEnabled)
            SoundMeterView(numberOfSegments: 10, currentValue: audioRecorder.normalizedPower)
                            .padding()
            Button("Generate Note") {
                self.transcribeEnabled = true
                print(audioRecorder.transcription)
                callOpenAI(prompt: audioRecorder.transcription)
            }
            .disabled(transcribeEnabled)
            .padding()
            
            Text(status)
                .padding()
            ScrollView{Text(response)
                    .padding()
            }
            
            RoundedButton(scanResult: $scanResult, isButtonEnabled: $isButtonEnabled)

                        Spacer()
                        
                        Text("Scan Result: \(scanResult)")
            
        }
        .onChange(of: scanResult) { newValue in
            if newValue != "No QR code detected" {
                sendPostRequest()
            }
        }
        
        
    }
    
    
    

   
    func sendPostRequest() {
        let urlString = "https://soaper.ai/qr.aspx"
        
        guard var urlComponents = URLComponents(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        let keyQueryItem = URLQueryItem(name: "key", value: scanResult)
        let responseQueryItem = URLQueryItem(name: "response", value: response)
        urlComponents.queryItems = [keyQueryItem, responseQueryItem]
        
        guard let url = urlComponents.url else {
            print("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "key": scanResult,
            "response": response
        ]
        print(scanResult)
        print(response)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted)
        
        } catch let error {
            print(error.localizedDescription)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let data = data, error == nil else {
                print(error?.localizedDescription ?? "No data")
                return
            }

            //let responseString = String(data: data, encoding: .utf8)
            //DispatchQueue.main.async {
            //    self.response = responseString ?? ""
            //}
        }

        task.resume()
        print("Full POST request URL: \(urlComponents.string ?? "Invalid URL")")
    }

    
    private func callOpenAI(prompt: String) {
        print("calling chatgpt...")
        self.status = "Generating Note..."
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            let apiKey = "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" // Replace this with your actual API key
print ("request sent")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody: [String: Any] = [
                "model": "gpt-3.5-turbo",
                "messages": [
                          
                          ["role": "user", "content": "write the subjective portion of a soap note based on the following transcript: \(prompt). if information is not included in the transcript, explicitly state that it is not provided."]
                      ],
                "max_tokens": 1500,
                "temperature": 0,
                "top_p": 1,
                "n": 1
            ]

            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data {
                    print(data)
                    
                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                        print(json)
                        
                        if let completions = json?["choices"] as? [[String: Any]] {
                            if let message = completions.first?["message"] as? [String: Any],
                               let content = message["content"] as? String {
                                DispatchQueue.main.async {
                                    self.response = content.trimmingCharacters(in: .whitespacesAndNewlines)
                                    isButtonEnabled = true
                                    self.status = ""
                                }
                            }
                        }
                    }
                    catch {
                        print("Error decoding JSON")
                        self.status = "Sorry, an error occured"
                    }
                } else {
                    print("Error: \(error?.localizedDescription ?? "Unknown error")")
                    self.status = "Sorry, an error occured"
                }
            }.resume()
        }
    
}



struct TranscriptionResponse: Codable {
    let text: String
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
