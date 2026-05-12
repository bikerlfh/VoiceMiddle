import VMCore

/// Observable event emitted by a ``TranslationPipeline`` for HUD / log
/// subscribers.
///
/// - ``partial``: the upstream STT delivered a non-final transcript for the
///   in-flight utterance. ``original`` is the most recent best guess.
/// - ``final``: a complete utterance has been translated; ``original`` is the
///   recognized source text and ``translated`` is the translator output. The
///   pipeline emits this immediately before handing the text to TTS.
/// - ``error``: a recoverable error occurred somewhere in the pipeline
///   (typically STT or translator). The pipeline does not stop; observers
///   may surface the message to the user.
public enum TranscriptEvent: Hashable, Sendable {
    case partial(direction: Direction, original: String)
    case final(direction: Direction, original: String, translated: String)
    case error(direction: Direction, message: String)
}
