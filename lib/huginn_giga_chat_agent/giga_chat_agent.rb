# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

require 'securerandom'

module Agents
  class GigaChatAgent < Agent
    include WebRequestConcern
    include FormConfigurable

    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description <<~MD
      GigaChat Agent предоставляет интеграцию с языковыми моделями GigaChat от Сбера через Huginn.

      ### Основные параметры
      `credentials`: Ключ авторизации для GigaChat API (обязательно)<br>
      `scope`: Версия API ('GIGACHAT_API_PERS', 'GIGACHAT_API_B2B' или 'GIGACHAT_API_CORP')<br>
      `model`: Название модели (по умолчанию 'GigaChat')<br>
      `verify_ssl`: Проверять HTTPS-сертификаты (по умолчанию 'true')<br>

      ### Настройки генерации
      `system_prompt`: Системный промпт (по умолчанию 'Выдели основные мысли из статьи.')<br>
      `user_prompt`: Пользовательский промпт с поддержкой Liquid (обязательно)<br>
      `temperature`: Креативность ответов (0-2, по умолчанию 0.1)<br>
      `max_tokens`: Максимальное количество токенов (по умолчанию 2000)<br>
    MD

    event_description <<~MD
      События содержат оригинальный payload с добавленным ответом модели:
      ```json
      {
        "completion": {
          "text": "Ответ модели",
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 20,
            "total_tokens": 30
          },
          "model": "GigaChat"
        }
      }
      ```
    MD

    form_configurable :credentials, type: :string
    form_configurable :scope, type: :array, values: ['GIGACHAT_API_PERS', 'GIGACHAT_API_B2B', 'GIGACHAT_API_CORP']
    form_configurable :model, type: :string
    form_configurable :verify_ssl, type: :boolean
    form_configurable :system_prompt, type: :text
    form_configurable :user_prompt, type: :text
    form_configurable :temperature, type: :number
    form_configurable :max_tokens, type: :number
    form_configurable :expected_receive_period_in_days, type: :number, html_options: { min: 1 }

    def default_options
      {
        'credentials' => '',
        'scope' => 'GIGACHAT_API_PERS',
        'model' => 'GigaChat',
        'verify_ssl' => 'true',
        'system_prompt' => 'Выдели основные мысли из статьи.',
        'user_prompt' => '{{message}}',
        'temperature' => 0.1,
        'max_tokens' => 2000,
        'expected_receive_period_in_days' => '2'
      }
    end

    def validate_options
      errors.add(:base, "credentials обязателен") unless options['credentials'].present?
      errors.add(:base, "scope обязателен") unless options['scope'].present?
      errors.add(:base, "user_prompt обязателен") unless options['user_prompt'].present?

      if options['temperature'].present?
        temp = options['temperature'].to_f
        errors.add(:base, "temperature должен быть между 0 и 2") unless temp.between?(0, 2)
      end

      if options['max_tokens'].present?
        errors.add(:base, "max_tokens должен быть положительным числом") unless options['max_tokens'].to_i > 0
      end
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        handle_event(event)
      end
    end

    private

    def handle_event(event)
      interpolate_with(event) do
        token = get_access_token
        return unless token

        response = send_completion_request(
          system_prompt: interpolated['system_prompt'],
          user_prompt: interpolated['user_prompt'],
          temperature: interpolated['temperature'].to_f,
          max_tokens: interpolated['max_tokens'].to_i,
          token: token
        )

        if response && response['choices']
          create_completion_event(event.payload, response)
          log "Запрос к GigaChat успешен: #{response.inspect}"
        else
          error "Не удалось получить ответ от GigaChat"
        end
      end
    rescue => e
      error "Ошибка обработки события: #{e.message}"
    end

    def get_access_token
      response = faraday.post(
        "https://ngw.devices.sberbank.ru:9443/api/v2/oauth",
        { scope: interpolated['scope'] }.to_query,
        {
          'Content-Type' => 'application/x-www-form-urlencoded',
          'Accept' => 'application/json',
          'RqUID' => SecureRandom.uuid,
          'Authorization' => "Basic #{interpolated['credentials']}"
        }
      )

      if response.success?
        JSON.parse(response.body)['access_token']
      else
        error "Не удалось получить токен доступа: #{response.body}"
        nil
      end
    end

    def send_completion_request(system_prompt:, user_prompt:, temperature:, max_tokens:, token:)
      request_body = {
        model: interpolated['model'],
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: user_prompt }
        ],
        temperature: temperature,
        max_tokens: max_tokens,
        stream: false
      }

      response = faraday.post(
        "https://gigachat.devices.sberbank.ru/api/v1/chat/completions",
        request_body.to_json,
        {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json',
          'Authorization' => "Bearer #{token}",
          'X-Request-ID' => SecureRandom.uuid
        }
      ) do |req|
        req.options[:open_timeout] = 5
        req.options[:timeout] = 30
        req.options[:verify_ssl] = boolify(interpolated['verify_ssl'])
      end

      response.success? ? JSON.parse(response.body) : nil
    end

    def create_completion_event(original_payload, response)
      choice = response['choices'][0]
      text = choice['message']['content']
      usage = response['usage']

      completion_data = {
        'text' => text,
        'usage' => {
          'prompt_tokens' => usage['prompt_tokens'],
          'completion_tokens' => usage['completion_tokens'],
          'total_tokens' => usage['total_tokens']
        },
        'model' => response['model']
      }

      create_event payload: original_payload.merge('completion' => completion_data)
    end
  end
end
