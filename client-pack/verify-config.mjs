#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const configPath = process.env.OPENCLAW_CONFIG_PATH || '/data/.openclaw/openclaw.json';
const defaultModel = process.env.CLAWDBOT_DEFAULT_MODEL || 'deepseek/deepseek-chat';
const vkEnabled = /^(true|1|yes|on)$/i.test(process.env.CLAWDBOT_ENABLE_VK || 'false');
const pluginRoot = process.env.OPENCLAW_PLUGINS_DIR || '/data/openclaw-plugins';

function log(message) {
  console.log(`[verify-config] ${message}`);
}

function fail(message) {
  console.error(`[verify-config] ERROR: ${message}`);
  process.exitCode = 1;
}

function readJsonLike(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`cannot parse ${filePath} as JSON after OpenClaw validation: ${error.message}`);
  }
}

function get(obj, dottedPath) {
  return dottedPath.split('.').reduce((acc, key) => (acc == null ? undefined : acc[key]), obj);
}

function hasOwn(obj, key) {
  return Object.prototype.hasOwnProperty.call(obj || {}, key);
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function boolIs(value, expected) {
  return value === expected;
}

function checkDefaultModel(config) {
  const primary = get(config, 'agents.defaults.model.primary');
  if (primary !== defaultModel) {
    fail(`agents.defaults.model.primary must be ${defaultModel}, got ${JSON.stringify(primary)}`);
  } else {
    log(`default model ok: ${defaultModel}`);
  }

  const models = get(config, 'agents.defaults.models');
  if (!isObject(models)) {
    fail('agents.defaults.models must exist and be an object');
  } else if (!hasOwn(models, defaultModel)) {
    fail(`agents.defaults.models must contain ${defaultModel}`);
  } else {
    log(`default model catalog ok: ${defaultModel}`);
  }

  const agents = get(config, 'agents.list');
  if (Array.isArray(agents)) {
    for (const agent of agents) {
      if (!agent || !agent.id) continue;
      if (hasOwn(agent, 'model') || hasOwn(agent, 'models')) {
        fail(`agent ${agent.id} must inherit default model; remove agent-level model/models override`);
      }
    }
    log(`agent model inheritance checked: ${agents.length} agents`);
  } else {
    fail('agents.list must exist and be an array');
  }
}

function checkPlugins(config) {
  if (!boolIs(get(config, 'plugins.enabled'), true)) {
    fail('plugins.enabled must be true');
  } else {
    log('plugins.enabled ok');
  }

  const paths = get(config, 'plugins.load.paths');
  if (!Array.isArray(paths)) {
    fail('plugins.load.paths must exist and be an array');
  } else if (!paths.some((item) => typeof item === 'string' && (item === pluginRoot || item.startsWith(`${pluginRoot}/`)))) {
    fail(`plugins.load.paths must include ${pluginRoot} or a child path`);
  } else {
    log(`plugins load path ok: ${pluginRoot}`);
  }

  const entries = get(config, 'plugins.entries') || {};
  const vkEntry = entries.vk || entries['openclaw-channel-vk'] || entries['vk-plugin'];
  if (vkEnabled) {
    if (!vkEntry || vkEntry.enabled !== true) {
      fail('VK enabled: plugins.entries must include an enabled VK entry');
    } else {
      log('VK plugin entry ok');
    }
  } else if (vkEntry && vkEntry.enabled === true) {
    fail('VK disabled: VK plugin entry must be absent or disabled');
  } else {
    log('VK plugin disabled ok');
  }
}

function checkChannels(config) {
  const channels = get(config, 'channels');
  if (!isObject(channels)) {
    fail('channels must exist and be an object');
    return;
  }

  const vkChannel = channels.vk || {};
  if (vkEnabled) {
    if (vkChannel.enabled !== true) {
      fail('VK enabled: channels.vk.enabled must be true');
    } else {
      log('VK channel enabled ok');
    }
  } else if (vkChannel.enabled === true) {
    fail('VK disabled: channels.vk.enabled must not be true');
  } else {
    log('VK channel disabled ok');
  }
}

function checkCommands(config) {
  const native = get(config, 'commands.native');
  const nativeSkills = get(config, 'commands.nativeSkills');
  const restart = get(config, 'commands.restart');

  if (native !== 'auto') fail(`commands.native must be "auto", got ${JSON.stringify(native)}`);
  else log('commands.native ok');

  if (nativeSkills !== 'auto') fail(`commands.nativeSkills must be "auto", got ${JSON.stringify(nativeSkills)}`);
  else log('commands.nativeSkills ok');

  if (restart !== true) fail(`commands.restart must be true, got ${JSON.stringify(restart)}`);
  else log('commands.restart ok');
}

function main() {
  log(`verify start: ${configPath}`);
  if (!fs.existsSync(configPath)) {
    fail(`config missing: ${configPath}`);
    process.exit();
  }

  const config = readJsonLike(configPath);
  checkDefaultModel(config);
  checkPlugins(config);
  checkChannels(config);
  checkCommands(config);

  if (process.exitCode) {
    log('verify failed');
    process.exit();
  }
  log('verify ok');
}

main();
