require 'twilio-ruby'
require 'rest_client'
require 'nokogiri'
require 'renee'
require 'yajl'
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
    attr_reader :result

    def initialize(result)
      @result = result
    end

    def link
      @link ||= Nokogiri::HTML(@result).css('a').first.inner_text
    end
  end
end

account_sid = ENV['TWILIO_ACCOUNT_SID']
auth_token = ENV['TWILIO_AUTH_TOKEN']
twilio_number = ENV['TWILIO_NUMBER']

# set up a client to talk to the Twilio REST API
client = Twilio::REST::Client.new(account_sid, auth_token)
$client = client.account

use Rack::CommonLogger
use Rack::ShowExceptions
run Renee {
  get do
    body = request['body']
    parts = body.strip.split(/\s+/)
    query = parts.shift
    results = DuckDuckTwilio::Results.new(Yajl::Parser.new.parse(RestClient.get("http://duckduckgo.com/?q=#{CGI.escape(query)}&o=json")))
    case parts.size
    when 0
      buf = []
      results.results.each_with_index{|r,i| buf << "#{i + 1}. #{r.link}"}
      $client.sms.messages.create({:from => "+#{twilio_number}", :body => buf.join(" ")})
      halt :ok
    when 1
      doc = Nokogiri::HTML(results.results[Integer(parts.first) - 1].result)
      doc.search('//p/*').each do |n| 
        n.replace(n.content) unless (%w[i b].include?(n.name))
      end
      $client.sms.messages.create({:from => "+#{twilio_number}", :body => doc.to_s})
      halt :ok
    end
  end
}