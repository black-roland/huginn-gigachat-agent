# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

module Agents
  class GigaChatEmbeddingClassifierAgent < Agent
    include WebRequestConcern

    cannot_be_scheduled!
    can_dry_run!
    no_bulk_receive!

    description <<~MD
      GigaChat Embedding Classifier Agent использует эмбеддинги GigaChat для классификации текста по заданным меткам.

      ### Основные параметры
      `credentials`: Ключ авторизации для GigaChat API (обязательно)<br>
      `scope`: Версия API ('GIGACHAT_API_PERS', 'GIGACHAT_API_B2B' или 'GIGACHAT_API_CORP')<br>
      `labels`: Массив меток для классификации (обязательно)<br>
      `text`: Текст для классификации с поддержкой Liquid (обязательно)<br>
      `min_similarity`: Минимальное значение косинусного сходства (0-1, по умолчанию 0.7)<br>
      `model`: Модель для эмбеддингов ('Embeddings' или 'EmbeddingsGigaR')<br>

      ### Принцип работы
      Агент вычисляет эмбеддинги для каждой метки и входящего текста, затем находит наиболее подходящие метки на основе косинусного сходства.
      Метки, чье сходство превышает `min_similarity`, добавляются в выходное событие.
    MD

    event_description <<~MD
      События содержат оригинальный payload с добавленными метками:
      ```json
      {
        "labels": ["label1", "label2"],
        "similarities": {
          "label1": 0.85,
          "label2": 0.78
        }
      }
      ```
    MD

    def default_options
      {
        'credentials' => '',
        'scope' => 'GIGACHAT_API_PERS',
        'labels' => [],
        'text' => '{{title}} {{description}}',
        'min_similarity' => '0.7',
        'model' => 'Embeddings',
        'expected_receive_period_in_days' => '2'
      }
    end

    def validate_options
      errors.add(:base, "credentials обязателен") unless options['credentials'].present?
      errors.add(:base, "labels обязателен") unless options['labels'].present?
      errors.add(:base, "text обязателен") unless options['text'].present?

      if options['min_similarity'].present?
        min_sim = options['min_similarity'].to_f
        errors.add(:base, "min_similarity должен быть между 0 и 1") unless min_sim.between?(0, 1)
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
        label_embeddings = get_label_embeddings

        text_to_classify = interpolated['text']
        return if text_to_classify.blank?

        text_embedding = get_text_embedding(text_to_classify)
        return unless text_embedding

        similarities = calculate_similarities(text_embedding, label_embeddings)

        selected_labels = select_labels(similarities)

        create_event payload: event.payload.merge(
          'labels' => selected_labels.keys,
          'similarities' => similarities
        )
      end
    rescue => e
      error "Ошибка обработки события: #{e.message}\n#{e.backtrace.join("\n")}"
    end

    def get_label_embeddings
      # Используем memory как кэш для эмбеддингов меток
      memory['label_embeddings'] ||= {}
      labels = interpolated['labels']

      # Вычисляем эмбеддинги для отсутствующих меток
      labels_to_process = labels.reject { |label| memory['label_embeddings'][label].present? }
      unless labels_to_process.empty?
        log("Запрашиваю эмбеддинги для меток: #{labels_to_process.join(', ')}")
      end

      labels.each do |label|
        next if memory['label_embeddings'][label].present?

        embedding = get_embedding(label)
        if embedding
          memory['label_embeddings'][label] = embedding
          log("Получен эмбеддинг для метки: #{label}")
        else
          log("Не удалось получить эмбеддинг для метки: #{label}")
        end
      end

      memory['label_embeddings']
    end

    def get_text_embedding(text)
      log("Запрашиваю эмбеддинг для текста: #{text.truncate(50)}")
      embedding = get_embedding(text)
      if embedding
        log("Получен эмбеддинг для текста")
      else
        log("Не удалось получить эмбеддинг для текста")
      end
      embedding
    end

    def get_embedding(text)
      token = get_access_token
      return unless token

      response = send_embedding_request(text, token)
      return unless response && response['data'] && response['data'][0]

      response['data'][0]['embedding']
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

    def send_embedding_request(text, token)
      request_body = {
        model: interpolated['model'],
        input: [text]
      }

      headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'Authorization' => "Bearer #{token}",
        'X-Request-ID' => SecureRandom.uuid
      }

      response = faraday.post(
        "https://gigachat.devices.sberbank.ru/api/v1/embeddings",
        request_body.to_json,
        headers
      )

      response.success? ? JSON.parse(response.body) : nil
    end

    def calculate_similarities(text_embedding, label_embeddings)
      similarities = {}

      label_embeddings.each do |label, label_embedding|
        similarity = cosine_similarity(text_embedding, label_embedding)
        similarities[label] = similarity
      end

      log("Рассчитаны сходства: #{similarities}")
      similarities
    end

    def cosine_similarity(vec_a, vec_b)
      dot_product = vec_a.zip(vec_b).map { |a, b| a * b }.sum
      norm_a = Math.sqrt(vec_a.map { |x| x**2 }.sum)
      norm_b = Math.sqrt(vec_b.map { |x| x**2 }.sum)

      dot_product / (norm_a * norm_b)
    end

    def select_labels(similarities)
      min_similarity = interpolated['min_similarity'].to_f
      selected = similarities.select { |_, similarity| similarity >= min_similarity }
      log("Выбраны метки с сходством >= #{min_similarity}: #{selected.keys}")
      selected
    end

    def faraday
      ca_file = File.join(File.dirname(__FILE__), '..', '..', 'certs', 'russian_trusted_root_ca.cer')
      unless File.exist?(ca_file)
        error "Файл сертификата russian_trusted_root_ca.cer не найден в репозитории"
        return super
      end

      faraday_options = {
        ssl: {
          verify: true,
          ca_file: ca_file
        }
      }

      @faraday ||= Faraday.new(faraday_options) { |builder|
        if parse_body?
          builder.response :json
        end

        builder.response :character_encoding,
                         force_encoding: interpolated['force_encoding'].presence,
                         default_encoding:,
                         unzip: interpolated['unzip'].presence

        builder.headers = headers if headers.length > 0

        builder.headers[:user_agent] = user_agent

        builder.proxy = interpolated['proxy'].presence

        unless boolify(interpolated['disable_redirect_follow'])
          require 'faraday/follow_redirects'
          builder.response :follow_redirects
        end

        builder.request :multipart
        builder.request :url_encoded

        if boolify(interpolated['disable_url_encoding'])
          builder.options.params_encoder = DoNotEncoder
        end

        builder.options.timeout = (Delayed::Worker.max_run_time.seconds - 2).to_i

        if userinfo = basic_auth_credentials
          builder.request :authorization, :basic, *userinfo
        end

        builder.request :gzip

        case backend = faraday_backend
        when :typhoeus
          require "faraday/#{backend}"
          builder.adapter backend, accept_encoding: nil
        when :httpclient, :em_http
          require "faraday/#{backend}"
          builder.adapter backend
        end
      }
    end
  end
end
