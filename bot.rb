#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'telegram/bot'
require 'logger'
require 'hashie'
require 'google-search'
require 'open-uri'
require 'json'

$log = Logger.new STDOUT
$log.datetime_format = "%Y-%m-%d %H:%M:%S"

require_relative 'config'

def get_results message
  regexp = /^https?:\/\/xkcd\.com\/(\d+)\/$/
  info = []

  Google::Search::Web.new(query: "site:xkcd.com #{message.query}").each do |res|
    next unless res.uri =~ regexp
    id = $1.to_i
    item = Hashie::Mash.new JSON.load(open("http://xkcd.com/#{id}/info.0.json")).merge url: res.uri
    info << item
    break if info.length >= 3
  end

  $log.debug do
    "Got data for #{message.query}:" +
      (info.map {|item| [item.num, item.title]}).inspect
  end

  info.map do |item|
    Telegram::Bot::Types::InlineQueryResultArticle.new id: item.num,
                                                       title: item.title,
                                                       message_text: item.url,
                                                       thumb_url: item.img
  end
end

Telegram::Bot::Client.run(TOKEN) do |bot|
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
