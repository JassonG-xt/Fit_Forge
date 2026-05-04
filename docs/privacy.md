# Privacy and Safety

FitForge is designed as an offline-first fitness assistant.

## Data Storage

- Profile, workout, body metric, achievement, theme, and recovery data are stored locally on the device through Flutter local storage.
- Coach Agent local logs may store user messages, assistant messages, suggested actions, and action outcomes in local storage. Logs are capped, long message text is truncated, and obvious health/body terms receive basic redaction before persistence. Users can clear these logs from the Coach privacy banner / Settings surface.
- The JSON export feature copies user data to the clipboard so the user can back it up or move it manually. Exports include local body, workout, profile, achievement, and settings data, but do not include `AgentEventLog`.
- The app does not currently provide cloud sync, accounts, remote analytics, or crash reporting.

## User Control

- Users can export their data from Settings.
- Users can import a previous export from the clipboard. Import applies size, schema, and numeric bounds checks before replacing local state.
- Users can clear all app data from Settings.

These controls reduce accidental exposure and malformed import risk, but local storage is still plaintext platform storage; they are not encryption or a privacy guarantee.

## Safety Notice

FitForge provides general fitness and nutrition assistance. It is not medical advice, diagnosis, or treatment. Users with injuries, medical conditions, pregnancy, eating disorders, or other health concerns should consult a qualified professional before following training or nutrition suggestions.

## Future Integrations

Planned integrations such as crash reporting, Health Connect, HealthKit, notifications, or cloud sync must update this document before release and clearly state what data is collected, where it is stored, and how users can opt out.
