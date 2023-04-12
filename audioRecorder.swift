//
//  audioRecorder.swift
//  test3
//
//  Created by Geng Szoa on 4/11/23.
//  Copyright © 2023 lingzhou125@gmail.com. All rights reserved.
//

import Foundation
import AVFoundation
import SwiftUI


class AudioRecorder: NSObject, ObservableObject {
    var audioRecorder: AVAudioRecorder!
    @Published var isRecording = false
    var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false

    private var silenceDetectionTimer: Timer?
    private let silenceThreshold: Float = -40.0 // Adjust this value to adjust the sensitivity of the silence detection
    private let silenceDetectionInterval: TimeInterval = 0.1 // Adjust this value to change the frequency of silence checks
    
    @Published var transcription = ""
    @Published var normalizedPower: CGFloat = 0.0

    func startRecording() {
        
        setupAudioSession()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording.m4a")
        print("Recording file URL: \(audioFilename)")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
                    audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
                    audioRecorder.delegate = self
                    audioRecorder.isMeteringEnabled = true // Enable metering to detect silence
                    audioRecorder.record()
                    isRecording = true

                    // Start silence detection timer
                    silenceDetectionTimer = Timer.scheduledTimer(withTimeInterval: silenceDetectionInterval, repeats: true) { _ in
                        self.checkForSilence()
                    }
                } catch {
                    print("Could not start recording")
                }
    }

    func stopRecording(shouldTranscribe: Bool = false) {
        audioRecorder.stop()
        isRecording = false
        
        // Stop the silence detection timer
        silenceDetectionTimer?.invalidate()
        silenceDetectionTimer = nil
        
    

            // Transcribe the last bit of audio
        if shouldTranscribe {
            let audioFileURL = audioRecorder.url
            print ("audiorecorder stopped")
            processAudioFile(audioFileURL, model: "whisper-1")
            }
        
    }
    
    private func checkForSilence() {
        audioRecorder.updateMeters()
        let currentPower = audioRecorder.averagePower(forChannel: 0)

        //for live meter
        let normalizedPower = ((currentPower + 160) / 160)
        self.normalizedPower = CGFloat(min(max(normalizedPower, 0), 1))
        
        if currentPower < silenceThreshold {
            // Detected silence
            let audioFileURL = audioRecorder.url
            
            // Calculate the recording duration
            let duration = audioRecorder.currentTime

            // Stop the current recording and start a new one
            stopRecording(shouldTranscribe: false)
            

            // Only send the audio file for transcription if the duration is longer than the threshold
            let durationThreshold: TimeInterval = 0.5 // Adjust the threshold value as needed
            if duration > durationThreshold {
                // Send the recorded audio file to the Whisper API and update the transcription
                // Replace "your-model-name" with the appropriate model name
                processAudioFile(audioFileURL, model: "whisper-1")
                
            }
            startRecording()
        }
    }

    private func processAudioFile(_ fileURL: URL, model: String) {
        print("sending for transcription \(fileURL)")
        let apiKey = "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" // Replace this with your OpenAI API key

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = NSMutableData()

        let data = try! Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body as Data

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            } else if let data = data, let response = response as? HTTPURLResponse {
                if response.statusCode == 200 {
                    if let decodedData = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
                        DispatchQueue.main.async {
                            self.transcription += "\n" + decodedData.text // Append the new transcription text
                            // callOpenAI(prompt: decodedData.text)
                            print (self.transcription)
                        }
                    } else {
                        print("Invalid response data")
                        //self.status = "Sorry, an error occured"
                    }
                } else {
                    print("Unexpected response status code: \(response.statusCode)")
                    //self.status = "Sorry, an error occured"
                }
            } else {
                print("Unexpected error")
                //self.status = "Sorry, an error occured"
            }
        }.resume()
    }

        


    func playRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording.m4a")
        print("playing recording")
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioFilename)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Could not play recording")
        }
    }

    func stopPlaying() {
        audioPlayer?.stop()
        isPlaying = false
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording failed")
         
        }
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}
