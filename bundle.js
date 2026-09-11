// Passkeys Web SDK stub — required by supabase_flutter plugin
window.PasskeyAuthenticator = {
  init: function() {},
  register: function() { return Promise.reject(JSON.stringify({code: 'not-supported', message: 'Passkeys not configured', details: ''})); },
  login: function() { return Promise.reject(JSON.stringify({code: 'not-supported', message: 'Passkeys not configured', details: ''})); },
  cancelCurrentAuthenticatorOperation: function() {},
  hasPasskeySupport: function() { return false; },
  isUserVerifyingPlatformAuthenticatorAvailable: function() { return Promise.resolve(false); },
  isConditionalMediationAvailable: function() { return Promise.resolve(false); },
};
