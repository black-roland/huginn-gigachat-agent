# Huginn GigaChat Agent

Агент для интеграции GigaChat с Huginn. Позволяет использовать мощь языковых моделей GigaChat для обработки текста в ваших автоматизированных сценариях.

## Ключевые возможности

- Работа с официальным API GigaChat
- Поддержка всех моделей GigaChat (**GigaChat-Pro**, **GigaChat-Max**)
- Гибкая настройка промптов через Liquid-шаблоны
- Контроль креативности (параметр температуры 0-2)
- Ограничение длины ответа (максимальное число токенов)
- Поддержка кэширования контекста с помощью X-Session-ID
- Поддержка разных сфер применения (персональные, B2B и корпоративные решения)
- Автоматическое управление токенами доступа

## Установка

Добавьте в файл `.env` вашего Huginn:

```bash
ADDITIONAL_GEMS="huginn_giga_chat_agent(github: black-roland/huginn-gigachat-agent)"
```

Затем выполните:

```bash
bundle
```

## Настройка агента

### Обязательные параметры:
- `credentials` - Ключ авторизации для GigaChat API (Basic Auth)
- `scope` - Сфера применения (`GIGACHAT_API_PERS`, `GIGACHAT_API_B2B`, `GIGACHAT_API_CORP`)
- `user_prompt` - Пользовательский запрос (поддерживает Liquid-шаблоны)

### Основные настройки:
- `model` - Название модели (`GigaChat`, `GigaChat-Pro`, `GigaChat-Max`)
- `system_prompt` - Системный промпт (определяет поведение модели)
- `temperature` (0-2) - Управление креативностью ответов
- `max_tokens` - Максимальное количество токенов в ответе
- `session_id` - Необязательный идентификатор сессии (произвольная строка) для кэширования контекста

## Примеры использования

### Базовый сценарий с кэшированием:
```yaml
scope: GIGACHAT_API_PERS
model: GigaChat-Max
system_prompt: "Ты - помощник, который анализирует тексты"
user_prompt: "Выдели ключевые темы из текста: {{text}}"
temperature: 0.3
max_tokens: 2000
session_id: "my-conversation-123"
```

## Формат выходных данных

События содержат оригинальный payload с добавленным ответом модели:

```json
{
  "completion": {
    "text": "Ответ модели",
    "usage": {
      "prompt_tokens": 150,
      "completion_tokens": 200,
      "total_tokens": 350,
      "precached_prompt_tokens": 100
    },
    "model": "GigaChat-Max"
  }
}
```
