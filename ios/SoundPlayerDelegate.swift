protocol SoundPlayerDelegate: AnyObject {
   func onSoundChunkPlayed(_ isFinal: Bool)
}
