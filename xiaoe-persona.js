window.XIAOE_PERSONA = {
  configUrl: './xiaoe-persona-v1.json',
  runtimeBridgeUrl: './docs/XIAOE_RUNTIME_IDENTITY_BRIDGE_V1.json',
  defaultMode: 'gentle_playful',

  async loadJson(url, label) {
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) throw new Error(`Unable to load ${label}`);
    return await res.json();
  },

  async load() {
    return await this.loadJson(this.configUrl, 'XiaoE Persona config');
  },

  async loadRuntimeProfile() {
    const [persona, runtimeBridge] = await Promise.all([
      this.loadJson(this.configUrl, 'XiaoE Persona config'),
      this.loadJson(this.runtimeBridgeUrl, 'XiaoE Runtime Identity Bridge')
    ]);

    return Object.freeze({
      persona,
      runtimeBridge,
      defaultMode: this.defaultMode
    });
  },

  resolveMode(config, modeName) {
    const key = modeName || this.defaultMode;
    return config.modes?.[key] || config.modes?.gentle_playful || config.modes?.gentle || null;
  }
};
