#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const configPath = process.env.OPENCLAW_CONFIG_PATH || '/data/.openclaw/openclaw.json';
const syncEnabled = /^(true|1|yes|on)$/i.test(process.env.CLAWDBOT_SYNC_CONFIG_FROM_ENV || 'true');
const pluginRoot = process.env.OPENCLAW_PLUGINS_DIR || '/data/.openclaw/extensions';
const defaultModel = process.env.CLAWDBOT_DEFAULT_MODEL || 'deepseek/deepseek-chat';
const vkEnabled = /^(true|1|yes|on)$/i.test(process.env.CLAWDBOT_ENABLE_VK || 'false');
const gatewayToken = process.env.OPENCLAW_GATEWAY_TOKEN || '';

function log(message) {
  console.log(`[sync-config-from-env] ${message}`);
}

function warn(message) {
  console.warn(`[sync-config-from-env] WARN ${message}`);
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function ensureObject(parent, key) {
  if (!isObject(parent[key])) parent[key] = {};
  return parent[key];
}

function uniqueStrings(values) {
  return [...new Set(values.filter((item) => typeof item === 'string' && item.trim()))];
}

function backup(filePath) {
  const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
  const backupPath = `${filePath}.bak.${stamp}`;
  fs.copyFileSync(filePath, backupPath);
  fs.chmodSync(backupPath, 0o600);
  return backupPath;
}

function writeJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
}

function tokenFingerprint(value) {
  if (!value) return 'empty';
  return crypto.createHash('sha256').update(value).digest('hex').slice(0, 12);
}

function main() {
  if (!syncEnabled) {
    log('skip: CLAWDBOT_SYNC_CONFIG_FROM_ENV=false');
    return;
  }

  if (!fs.existsSync(configPath)) {
    log(`skip: config not found at ${configPath}`);
    return;
  }

  let config;
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (error) {
    warn(`cannot parse config at ${configPath}: ${error.message}`);
    process.exitCode = 1;
    return;
  }

  const changes = [];

  const gateway = ensureObject(config, 'gateway');
  const gatewayAuth = ensureObject(gateway, 'auth');
  if (gatewayToken && gatewayAuth.token !== gatewayToken) {
    gatewayAuth.mode = 'token';
    gatewayAuth.token = gatewayToken;
    changes.push(`gateway.auth.token=${tokenFingerprint(gatewayToken)}`);
  }

  const agents = ensureObject(config, 'agents');
  const defaults = ensureObject(agents, 'defaults');
  const model = ensureObject(defaults, 'model');
  if (model.primary !== defaultModel) {
    model.primary = defaultModel;
    changes.push(`agents.defaults.model.primary=${defaultModel}`);
  }
  const models = ensureObject(defaults, 'models');
  if (!isObject(models[defaultModel])) {
    models[defaultModel] = {};
    changes.push(`agents.defaults.models.${defaultModel}=present`);
  }

  const plugins = ensureObject(config, 'plugins');
  plugins.enabled = true;
  const load = ensureObject(plugins, 'load');
  if (!Array.isArray(load.paths)) load.paths = [];
  const nextPaths = uniqueStrings([...load.paths, pluginRoot]);
  if (JSON.stringify(nextPaths) !== JSON.stringify(load.paths)) {
    load.paths = nextPaths;
    changes.push(`plugins.load.paths includes ${pluginRoot}`);
  }

  const pluginEntries = ensureObject(plugins, 'entries');
  const vkEntry = ensureObject(pluginEntries, 'vk');
  if (vkEntry.enabled !== vkEnabled) {
    vkEntry.enabled = vkEnabled;
    changes.push(`plugins.entries.vk.enabled=${vkEnabled}`);
  }

  const channels = ensureObject(config, 'channels');
  const vkChannel = ensureObject(channels, 'vk');
  if (vkChannel.enabled !== vkEnabled) {
    vkChannel.enabled = vkEnabled;
    changes.push(`channels.vk.enabled=${vkEnabled}`);
  }

  const commands = ensureObject(config, 'commands');
  if (commands.native !== 'auto') {
    commands.native = 'auto';
    changes.push('commands.native=auto');
  }
  if (commands.nativeSkills !== 'auto') {
    commands.nativeSkills = 'auto';
    changes.push('commands.nativeSkills=auto');
  }
  if (commands.restart !== true) {
    commands.restart = true;
    changes.push('commands.restart=true');
  }

  if (changes.length === 0) {
    log('ok: no changes needed');
    return;
  }

  const backupPath = backup(configPath);
  writeJson(configPath, config);
  log(`backup: ${backupPath}`);
  log(`updated: ${changes.join('; ')}`);
}

main();
