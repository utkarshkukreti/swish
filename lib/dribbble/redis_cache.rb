module Dribbble
  class RedisCache
    include HTTParty
    base_uri 'api.dribbble.com'

    MAX_HITS_PER_MINUTE = 55 # Padded down from actual 60 to be safe
    HIT_COUNTER_KEY = 'hits-this-minute'
    ONE_MINUTE = 60

    attr_reader :value

    def self.fetch(path, options)
      new(path, options).value
    end

    def initialize(path, options)
      @path = path
      @options = options

      if Dribbble::Config.enable_redis
        @connection = Redis.new
        @key = "#{path}::#{options.hash}"
        @value = cached_value
      else
        @value = api_response
      end 
    end

    def cached_value
      JSON.parse(@connection.get(@key) || cache_response)
    end

    def api_response
      self.class.get @path, :query => @options
    end

    private 

    def over_api_limit?
      @connection.get(HIT_COUNTER_KEY).to_i >= MAX_HITS_PER_MINUTE
    end

    def take_a_nap
      ttl = @connection.ttl(HIT_COUNTER_KEY).to_i
      sleep ttl if ttl > 0
    end

    def increase_hit_count
      ttl = @connection.ttl HIT_COUNTER_KEY
      ttl = ONE_MINUTE if ttl == -1
      val = @connection.get(HIT_COUNTER_KEY).to_i
      @connection.set HIT_COUNTER_KEY, val + 1
      @connection.expire HIT_COUNTER_KEY, ttl
    end

    def cache_response
      if over_api_limit?
        take_a_nap
        # TODO: Implement query queueing
        cache_response
      else
        live_value = api_response.to_json
        @connection.set @key, live_value
        @connection.expire @key, ONE_MINUTE
        increase_hit_count
        live_value
      end
    end
  end
end
