# ClawdBot Railway Client Pack v0.1 — быстрый запуск клиента

Цель: развернуть готовую клиентскую демо-сборку ClawdBot на Railway без ручной установки skills/plugins после деплоя.

## Что получает клиент

После deploy контейнер сам:

1. проверяет volume `/data`;
2. создаёт `/data/.openclaw`, `/data/workspace`, `/data/.clawdbot`;
3. создаёт `/data/.openclaw/openclaw.json`, если его ещё нет;
4. настраивает модель по умолчанию для всех агентов;
5. ставит skills из `/data/.clawdbot/skills.allowlist`;
6. ставит VK plugin только если `CLAWDBOT_ENABLE_VK=true`;
7. проверяет итоговый runtime и config;
8. пишет понятные логи `[clawdbot-entrypoint]`, `[skills-sync]`, `[verify-runtime]`, `[verify-config]`.

## Быстрый порядок запуска

### 1. Deploy from GitHub

Подключить этот fork к Railway как GitHub service.

### 2. Attach volume

Создать Railway Volume и примонтировать его строго в:

```text
/data
```

Без volume deploy должен упасть. Это нормально: сборка специально защищается от запуска без persistent state.

## Railway volume behavior

ClawdBot requires a Railway Volume mounted at `/data`.

There are two supported deploy modes:

1. Deploy from fork:
   - attach a Railway Volume manually;
   - set mount path to `/data`;
   - redeploy the service.

2. Deploy from Railway Template:
   - the template must include an attached volume on the ClawdBot service;
   - mount path must be `/data`;
   - the user should not create a second volume after deploy unless intentionally migrating data.

Redeploy behavior:

- redeploying the same Railway service reuses the existing attached volume;
- it does not create a new volume;
- do not add Dockerfile `VOLUME`;
- do not use pre-deploy commands to read or write `/data`.

The container checks `RAILWAY_VOLUME_MOUNT_PATH=/data` at runtime and exits early if the volume is missing or mounted at the wrong path.

### 3. Railway Variables

Открыть Railway → Service → Variables → RAW Editor.

Скопировать содержимое `.env.example` и заполнить реальные значения.

## Минимум для демо

Для демо обычно достаточно заполнить:

```env
SETUP_PASSWORD=
DEEPSEEK_API_KEY=
OPENCLAW_GATEWAY_TOKEN=
CLAWDBOT_GATEWAY_TOKEN=
CLAWDBOT_ENABLE_VK=false
```

Если VK нужен сразу:

```env
CLAWDBOT_ENABLE_VK=true
VK_COMMUNITY_TOKEN=
VK_GROUP_ID=
```

## Модель по умолчанию

По умолчанию все агенты должны наследовать одну модель:

```env
CLAWDBOT_DEFAULT_PROVIDER=deepseek
CLAWDBOT_DEFAULT_MODEL=deepseek/deepseek-chat
```

Итоговый config должен содержать:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "deepseek/deepseek-chat"
      },
      "models": {
        "deepseek/deepseek-chat": {}
      }
    }
  }
}
```

Агенты не должны иметь собственные `model` или `models`, иначе они перестанут наследовать default model.

## Skills

Source of truth для skills после первого запуска:

```text
/data/.clawdbot/skills.allowlist
```

Git-шаблон для первого запуска:

```text
client-pack/default/skills.list
```

Если нужно добавить skill уже работающему клиенту, добавить строку в:

```text
/data/.clawdbot/skills.allowlist
```

Фоновый helper доставит недостающий skill. Уже установленные skills не обновляются автоматически, потому что `update --all` может поменять поведение клиента.

```env
CLAWDBOT_SKILLS_UPDATE_ALL=false
```

## Plugins

Плагины должны жить на volume внутри OpenClaw state:

```text
/data/.openclaw/extensions
```

VK ставится только при:

```env
CLAWDBOT_ENABLE_VK=true
```

Если `CLAWDBOT_ENABLE_VK=false`, VK channel/plugin должен быть выключен в итоговом config.

## Зелёные логи после deploy

В Railway открыть текущий deployment → View logs.

Искать:

```text
[clawdbot-entrypoint] create first-boot OpenClaw config
[skills-sync] sync start
[verify-runtime] openclaw version ok
[verify-runtime] config valid
[verify-config] default model ok
[verify-config] default model catalog ok
[verify-config] plugins.enabled ok
[verify-config] plugins load path ok
[verify-config] VK channel disabled ok
[verify-config] commands.native ok
[verify-config] commands.nativeSkills ok
[verify-config] commands.restart ok
[verify-config] verify ok
[verify-runtime] verify ok
```

Если VK включён, вместо disabled должно быть:

```text
[verify-config] VK plugin entry ok
[verify-config] VK channel enabled ok
```

## Частые ошибки

### Volume не подключён

Лог:

```text
ERROR: Railway volume must be mounted at /data
```

Решение: подключить Railway Volume в `/data`.

### `/data` не writable

Лог:

```text
ERROR: /data is not writable
```

Решение: проверить mount path и права volume.

### Старый config уже есть

Лог:

```text
preserve existing OpenClaw config
```

Это значит, что `/data/.openclaw/openclaw.json` уже был создан раньше и entrypoint его не перетирает.

Если нужен новый чистый config, старый файл надо мигрировать/переименовать вручную на volume. Не удалять без backup.

### Config invariant failed

Лог:

```text
[verify-config] ERROR: ...
```

Смотреть, какая из 4 зон не прошла:

1. model;
2. plugins;
3. channels;
4. commands.

## Что нельзя делать в клиентском fork

Не править:

```text
src/*
```

Не включать по умолчанию:

```env
CLAWDBOT_SKILLS_UPDATE_ALL=true
CLAWDBOT_VERIFY_LIVE_MODEL=true
```

Не хранить в Git реальные значения:

```text
API keys
tokens
setup passwords
pixel ids
```

## Критерий готовности v0.1-rc1

Сборка считается готовой, если:

1. Railway deployment стал Active;
2. healthcheck прошёл;
3. logs содержат `[verify-runtime] verify ok`;
4. logs содержат `[verify-config] verify ok`;
5. skills ставятся или корректно skip-аются;
6. VK выключен по умолчанию;
7. redeploy не стирает `/data`.
