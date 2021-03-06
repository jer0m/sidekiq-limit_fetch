module Sidekiq::LimitFetch::Global
  module Monitor
    include Sidekiq::LimitFetch::Redis
    extend self

    HEARTBEAT_PREFIX = 'limit:heartbeat:'
    PROCESS_SET = 'limit:processes'
    HEARTBEAT_TTL = 18
    REFRESH_TIMEOUT = 10

    def start!(ttl=HEARTBEAT_TTL, timeout=REFRESH_TIMEOUT)
      Thread.new do
        loop do
          update_heartbeat ttl
          invalidate_old_processes
          sleep timeout
        end
      end
    end

    def all_processes
      redis {|it| it.smembers PROCESS_SET }
    end

    def old_processes
      all_processes.reject do |process|
        redis {|it| it.get heartbeat_key process }
      end
    end

    def remove_old_processes!
      redis do |it|
        old_processes.each {|process| it.srem PROCESS_SET, process }
      end
    end

    private

    def update_heartbeat(ttl)
      Sidekiq.redis do |it|
        it.pipelined do
          it.set heartbeat_key, true
          it.sadd PROCESS_SET, Selector.uuid
          it.expire heartbeat_key, ttl
        end
      end
    end

    def invalidate_old_processes
      Sidekiq.redis do |it|
        remove_old_processes!
        processes = all_processes

        Sidekiq::Queue.instances.each do |queue|
          queue.remove_locks_except! processes
        end
      end
    end

    def heartbeat_key(process=Selector.uuid)
      HEARTBEAT_PREFIX + process
    end
  end
end
