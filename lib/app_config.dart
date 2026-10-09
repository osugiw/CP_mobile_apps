// ── Demo mode ────────────────────────────────────────────────────────────────
// true  = no server calls at all; My Day, My Tasks and Ask Sally use sample data
//         so the UI can be tested without the Pi.
// false = talk to the real Pi server (also restore the IP below).
//
// Can also be set at build time: --dart-define=SALLY_DEMO=false
const bool kDemoMode = bool.fromEnvironment('SALLY_DEMO', defaultValue: true);

const String sallyApiBaseUrl = String.fromEnvironment(
  'SALLY_API_BASE_URL',
  // Pi server over Tailscale. Commented out for UI testing, restore to reconnect:
  // defaultValue: 'http://100.120.159.54:5001',
  defaultValue: '',
);

const String sallyDeviceId = String.fromEnvironment(
  'SALLY_DEVICE_ID',
  defaultValue: 'esp32_01',
);

// Bearer token for the Sally API (set at build time via --dart-define=SALLY_API_TOKEN=...)
const String sallyApiToken = String.fromEnvironment(
  'SALLY_API_TOKEN',
  defaultValue: '',
);

bool get isSallyApiConfigured => sallyApiBaseUrl.trim().isNotEmpty;
