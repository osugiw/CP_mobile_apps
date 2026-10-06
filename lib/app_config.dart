const String sallyApiBaseUrl = String.fromEnvironment(
  'SALLY_API_BASE_URL',
  defaultValue: 'http://100.120.159.54:5001',
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
