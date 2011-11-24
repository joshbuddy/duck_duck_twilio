require 'rest_client'
require 'nokogiri'
require 'renee'
require 'json'
require 'cgi'

module DuckDuckTwilio
  class Results
    attr_reader :results

    def initialize(results)
      @raw_results = results
      @results = map_results(@raw_results['RelatedTopics'])
    end

    private
    def map_results(results)
      mapped_results = results.map do |topic|
        if topic.key?("Result")
          Result.new(topic["Result"])
        elsif topic.key?("Topics")
          map_results(topic["Topics"])
        end
      end
      mapped_results.flatten!
      mapped_results
    end
  end

  class Result
    def initialize(result)
      @result = result
    end

    def link
      @link ||= Nokogiri::HTML(@result).css('a').first.inner_text
    end
  end
end

use Rack::CommonLogger
use Rack::ShowExceptions
run Renee {
  get do
    body = request['body']
    parts = body.strip.split(/\s+/)
    query = parts.shift
    results = DuckDuckTwilio::Results.new(JSON.parse(RestClient.get("http://duckduckgo.com/?q=#{CGI.escape(query)}&o=json")))
    case parts.size
    when 0
      buf = []
      results.results.each_with_index{|r,i| buf << "#{i + 1}. #{r.link}"}
      halt buf.join(" ")
    when 1
      halt results.results[Integer(parts.first) - 1].inspect
    end
  end
}