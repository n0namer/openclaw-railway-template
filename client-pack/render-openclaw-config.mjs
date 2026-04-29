#!/usr/bin/env node
import fs from 'node:fs';

const inputPath = process.argv[2] || '/app/client-pack/default/openclaw.template.json';
const renderedAt = new Date().toISOString();

function isTrue(value) {
  return /^(true|1|yes|on)$/i.test(String(value || ''));
}

function numberFromEnv(name, fallback) {
  const raw = process.env[name];
  if (raw == null || raw === '') return fallback;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return fallback;
  return parsed;
}

function stringFromEnv(name, fallback = '') {
  const value = process.env[name];
  if (value == null || value === '') return fallback;
  return String(value);
}

function replacementMap() {
  const vkEnabled = isTrue(process.env.CLAWDBOT_ENABLE_VK);
  const defaultModel = stringFromEnv('OPENCLAW_LLM_MODEL', stringFromEnv('CLAWDBOT_DEFAULT_MODEL', 'deepseek/deepseek-chat'));
  const llmBaseUrl = stringFromEnv('OPENCLAW_LLM_BASE_URL', 'https://api.deepseek.com');
  const openclawVersion = stringFromEnv('OPENCLAW_VERSION', '2026.4.23');
  const pluginsDir = stringFromEnv('OPENCLAW_PLUGINS_DIR', '/data/.openclaw/extensions');
  const gatewayToken = stringFromEnv('OPENCLAW_GATEWAY_TOKEN', '');
  const gatewayBindRaw = stringFromEnv('INTERNAL_GATEWAY_BIND', 'lan');
  const gatewayBind = gatewayBindRaw === 'lan' ? 'loopback' : gatewayBindRaw;

  return {
    OPENCLAW_VERSION: openclawVersion,
    CLAWDBOT_RENDERED_AT: renderedAt,
    DEEPSEEK_API_KEY: stringFromEnv('DEEPSEEK_API_KEY'),
    OPENCLAW_LLM_MODEL: defaultModel,
    OPENCLAW_LLM_BASE_URL: llmBaseUrl,
    CLAWDBOT_DEFAULT_MODEL: defaultModel,
    CLAWDBOT_ENABLE_VK_BOOL: vkEnabled,
    OPENCLAW_PLUGINS_DIR: pluginsDir,
    INTERNAL_GATEWAY_PORT_NUMBER: numberFromEnv('INTERNAL_GATEWAY_PORT', 18789),
    INTERNAL_GATEWAY_BIND: gatewayBind,
    OPENCLAW_GATEWAY_TOKEN: gatewayToken,
  };
}

function replaceTemplate(raw, vars) {
  let rendered = raw;
  for (const [key, value] of Object.entries(vars)) {
    const placeholder = new RegExp(`"\\$\\{${key}\\}"`, 'g');
    rendered = rendered.replace(placeholder, JSON.stringify(value));

    const inlinePlaceholder = new RegExp(`\\$\\{${key}\\}`, 'g');
    rendered = rendered.replace(inlinePlaceholder, String(value).replaceAll('\\', '\\\\').replaceAll('"', '\\"'));
  }
  return rendered;
}

function ensureDeepSeekProvider(parsed, defaultModel, baseUrl) {
  parsed.models ??= {};
  parsed.models.mode ??= 'merge';
  parsed.models.providers ??= {};
  parsed.models.providers.deepseek ??= {};
  parsed.models.providers.deepseek.baseUrl = baseUrl;
  parsed.models.providers.deepseek.api = 'openai-completions';
  parsed.models.providers.deepseek.models ??= [];

  const [, modelId = defaultModel] = defaultModel.split('/', 2);
  if (!parsed.models.providers.deepseek.models.some((item) => item && item.id === modelId)) {
    parsed.models.providers.deepseek.models.push({
      id: modelId,
      name: modelId,
      reasoning: false,
      input: ['text'],
      contextWindow: 128000,
      contextTokens: 96000,
      maxTokens: 8192,
    });
  }
}

function main() {
  const raw = fs.readFileSync(inputPath, 'utf8');
  const vars = replacementMap();
  const rendered = replaceTemplate(raw, vars);
  const parsed = JSON.parse(rendered);

  const vkEnabled = isTrue(process.env.CLAWDBOT_ENABLE_VK);
  parsed.channels ??= {};
  parsed.channels.vk ??= {};
  parsed.channels.vk.enabled = vkEnabled;

  parsed.plugins ??= {};
  parsed.plugins.enabled = true;
  parsed.plugins.load ??= {};
  parsed.plugins.load.paths ??= [];
  const pluginsDir = stringFromEnv('OPENCLAW_PLUGINS_DIR', '/data/.openclaw/extensions');
  if (!parsed.plugins.load.paths.includes(pluginsDir)) parsed.plugins.load.paths.push(pluginsDir);
  parsed.plugins.entries ??= {};
  parsed.plugins.entries.vk ??= {};
  parsed.plugins.entries.vk.enabled = vkEnabled;

  parsed.commands ??= {};
  parsed.commands.native = 'auto';
  parsed.commands.nativeSkills = 'auto';
  parsed.commands.restart = true;

  parsed.agents ??= {};
  parsed.agents.defaults ??= {};
  parsed.agents.defaults.model ??= {};
  const defaultModel = stringFromEnv('OPENCLAW_LLM_MODEL', stringFromEnv('CLAWDBOT_DEFAULT_MODEL', 'deepseek/deepseek-chat'));
  const llmBaseUrl = stringFromEnv('OPENCLAW_LLM_BASE_URL', 'https://api.deepseek.com');
  parsed.agents.defaults.model.primary = defaultModel;
  parsed.agents.defaults.models ??= {};
  parsed.agents.defaults.models[defaultModel] ??= {};
  parsed.agents.list ??= [{ id: 'main' }];
  for (const agent of parsed.agents.list) {
    if (agent && typeof agent === 'object') {
      delete agent.model;
      delete agent.models;
    }
  }

  ensureDeepSeekProvider(parsed, defaultModel, llmBaseUrl);
  process.stdout.write(`${JSON.stringify(parsed, null, 2)}\n`);
}

main();
