require 'chef/provider'
require File.join(File.dirname(__FILE__), 'client')
require File.join(File.dirname(__FILE__), 'cluster_data')

class Chef
  class Provider
    # Provides Class CouchbaseBucket < Provider
    class CouchbaseBucket < Provider
      include Couchbase::Client
      include Couchbase::ClusterData

      # rubocop:disable Metrics/AbcSize
      def load_current_resource
        @current_resource = Resource::CouchbaseBucket.new @new_resource.name
        @current_resource.bucket @new_resource.bucket
        @current_resource.cluster @new_resource.cluster
        # @current_resource.exists !!bucket_data
        @current_resource.exists !bucket_data.nil?

        # if @current_resource.exists
        return unless @current_resource.exists
        @current_resource.type bucket_type
        @current_resource.memory_quota_mb bucket_memory_quota_mb
        @current_resource.replicas bucket_replicas
      end
      # rubocop:enable Metrics/AbcSize

      def action_create
        if !@current_resource.exists
          create_bucket
        elsif @current_resource.memory_quota_mb != new_memory_quota_mb
          modify_bucket
        end
      end

      private

      def create_bucket
        post "/pools/#{@new_resource.cluster}/buckets", create_params
        new_resource.updated_by_last_action true
        Chef::Log.info "#{new_resource} created"
      end

      def modify_bucket
        post "/pools/#{@new_resource.cluster}/buckets/#{@new_resource.bucket}", modify_params
        new_resource.updated_by_last_action true
        Chef::Log.info "#{new_resource} memory_quota_mb changed to #{new_memory_quota_mb}"
      end

      def create_params
        {
          'authType' => 'sasl',
          'saslPassword' => '',
          'bucketType' => new_api_type,
          'name' => new_resource.bucket,
          'ramQuotaMB' => new_memory_quota_mb,
          'replicaNumber' => new_resource.replicas || 0
        }
      end

      def new_api_type
        new_resource.type == 'couchbase' ? 'membase' : new_resource.type
      end

      def modify_params
        {
          'ramQuotaMB' => new_memory_quota_mb
        }
      end

      def new_memory_quota_mb
        new_resource.memory_quota_mb || (new_resource.memory_quota_percent * pool_memory_quota_mb).to_i
      end

      def bucket_memory_quota_mb
        (bucket_data['quota']['rawRAM'] / 1024 / 1024).to_i
      end

      def bucket_replicas
        bucket_data['replicaNumber']
      end

      def bucket_type
        bucket_data['bucketType'] == 'membase' ? 'couchbase' : bucket_data['bucketType']
      end

      def bucket_data
        return @bucket_data if instance_variable_defined? '@bucket_data'

        @bucket_data ||= begin
          response = get "/pools/#{@new_resource.cluster}/buckets/#{@new_resource.bucket}"
          response.error! unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPNotFound)
          JSONCompat.from_json response.body if response.is_a? Net::HTTPSuccess
        end
      end
    end
  end
end
