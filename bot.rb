#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'telegram/bot'
require 'hashie'

$log = Logger.new STDOUT
$log.datetime_format = "%Y-%m-%d %H:%M:%S"

require_relative 'config'

SOMETHING_WENT_WRONG = Telegram::Bot::Types::InlineQueryResultArticle.new(
  id: -1,
  title: "Error",
  description: "Something went wrong!",
  input_message_content: Telegram::Bot::Types::InputTextMessageContent.new(
    message_text: "`Robert'); DROP TABLE Students;--`",
    parse_mode: "Markdown"
  )
).freeze

def get_results message
  results = Hashie::Mash.new(
    JSON.parse(
        Faraday.post("https://relevant-xkcd-backend.herokuapp.com/search", {search: message.query})
               .body
    )
  ).results

  $log.debug do
    "Got data for #{message.query}:" +
      (results.map {|item| [item.number, item.title]}).inspect
  end

  results.map do |item|
    Telegram::Bot::Types::InlineQueryResultArticle.new(
      id: item.number,
      title: item.title,
      input_message_content: Telegram::Bot::Types::InputTextMessageContent.new(
        message_text: "https://#{item.url}"
      ),
      url: "https://#{item.url}",
      thumb_url: item.image
    )
  end
rescue => e
  $log.error "Something went wrong while getting results: #{e}"
  [SOMETHING_WENT_WRONG]
end

Telegram::Bot::Client.run(TOKEN, logger: $log) do |bot|
  begin
    bot.listen do |message|
      $log.debug "Got message: #{message.id if message.respond_to? :id}: #{message} (#{message.class})"
      case message
      when Telegram::Bot::Types::InlineQuery
        begin
          bot.api.answer_inline_query inline_query_id: message.id, results: get_results(message)
        rescue Telegram::Bot::Exceptions::ResponseError => e
          $log.warn { "Ignoring API response: #{e}" }
        end
      when Telegram::Bot::Types::ChosenInlineResult
        $log.info { "#{message.from.username} shared xkcd #{message.result_id} by query #{message.query}" }
      end
    end
  rescue Interrupt
    $log.warn "Caught interrupt -- quitting"
  end
end
