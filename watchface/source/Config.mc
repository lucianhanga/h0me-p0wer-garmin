module Config {
    const API_URL =
        "https://h0me-p0wer.lucianhanga.stream/api/watch/status";

    // Same token/contract as the companion watch app (h0me-p0wer-garmin's
    // main project) - see that project's Config.mc for the full comment
    // on how it's generated/rotated. Lives in Secrets.mc (gitignored -
    // copy Secrets.mc.example to create it) so a real token never lands
    // in git.
    const API_TOKEN = Secrets.API_TOKEN;

    // A watch face runs all day, unlike the main watch app (which only
    // polls while the user has it open) - Background.registerForTemporalEvent
    // enforces its own device-dependent minimum interval regardless, but
    // 30 min is a deliberately conservative choice for all-day battery
    // life rather than relying on that floor.
    const REFRESH_MINUTES = 30;
}
