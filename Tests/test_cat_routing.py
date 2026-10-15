"""Guard the integrated command route; matching and cleanup have runtime fixtures."""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / "Sources/GroqVoiceInput"
coordinator = (root / "DictationCoordinator.swift").read_text()
controller = (root / "VoiceTypeController.swift").read_text()
assert coordinator.index("if consumeTranscript?(transcript)") < coordinator.index("if LanguagePolicy.shouldIntercept(transcript") < coordinator.index("let processed = TextPostProcessor.process")
assert "dictation.consumeTranscript =" in controller
assert "case .cooldown: return true" in controller
assert "catOverlay.dispose()" in controller
assert "if state != .idle { catOverlay.hide() }" in controller
assert "catConfiguration.imageData.flatMap" in controller
print("Integrated cat command routing checks passed")
