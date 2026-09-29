extension TVLink {
    /// A readable name for a webOS sound output id such as "external_arc".
    public nonisolated static func soundOutputName(_ id: String) -> String {
        switch id {
        case "tv_speaker": "TV Speakers"
        case "external_arc": "HDMI ARC"
        case "external_optical": "Optical"
        case "bt_soundbar": "Bluetooth"
        case "headphone": "Headphones"
        case "tv_external_speaker": "TV + Optical"
        case "tv_speaker_headphone": "TV + Headphones"
        case "lineout": "Line Out"
        case "mobile_phone": "Phone"
        default: id
        }
    }
}
