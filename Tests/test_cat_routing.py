"""Source contract checks for the private controller's greeting interception.

Runtime matching/cooldown and AppKit lifecycle are tested by the Swift fixtures.
These guards verify wiring without starting AVCaptureSession or using credentials.
"""
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / "Sources/GroqVoiceInput/main.swift").read_text()

def body(name):
    start = source.index(name)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[opening + 1:cursor - 1]

initial = body("private func handleTranscription(")
assert initial.index("consumeCatGreeting(transcript") < initial.index("LanguagePolicy.shouldIntercept")
retry = body("private func retryWithChineseHint(")
assert retry.index("consumeCatGreeting(retried") < retry.index("LanguagePolicy.shouldIntercept")
delivery = body("private func deliver(")
assert delivery.index("consumeCatGreeting(transcript") < delivery.index("TextPostProcessor.process") < delivery.index("copyAndPaste")
greeting = body("private func consumeCatGreeting(")
for forbidden in ("transcribe(", "copyAndPaste(", "NSSound", "activate("):
    assert forbidden not in greeting
assert "case .cooldown:" in greeting and greeting.count("discardRecording(url)") == 2
finish = body("private func handleRecordingFinished(")
assert finish.index("if recordingCancelled") < finish.index("readAPIKey()") < finish.index("transcribe(")
assert "awaitingRecordingFinish = true" in body("private func cancelRecording(")
assert "awaitingRecordingFinish = true" in body("private func stopRecording(")
assert "!awaitingRecordingFinish" in body("func toggleRecording(")
assert "catOverlay.dispose()" in body("func applicationWillTerminate(")
assert "catOverlay.hide()" in body("private func startRecording(")
assert "catOverlay.hide()" in body("private func stopRecording(")
assert "catOverlay.hide()" in body("private func cancelRecording(")
print("Cat controller source-routing contracts passed (no microphone/network/clipboard)")
