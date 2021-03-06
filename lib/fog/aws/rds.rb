module Fog
  module AWS
    class RDS < Fog::Service

      class IdentifierTaken < Fog::Errors::Error; end

      requires :aws_access_key_id, :aws_secret_access_key
      recognizes :region, :host, :path, :port, :scheme, :persistent

      request_path 'fog/aws/requests/rds'

      request :create_db_instance
      request :modify_db_instance
      request :describe_db_instances
      request :delete_db_instance
      request :reboot_db_instance
      request :create_db_instance_read_replica

      request :describe_db_snapshots
      request :create_db_snapshot
      request :delete_db_snapshot


      request :create_db_parameter_group
      request :delete_db_parameter_group
      request :modify_db_parameter_group
      request :describe_db_parameter_groups

      request :describe_db_security_groups
      request :create_db_security_group
      request :delete_db_security_group
      request :authorize_db_security_group_ingress
      request :revoke_db_security_group_ingress

      request :describe_db_parameters

      request :restore_db_instance_from_db_snapshot
      request :restore_db_instance_to_point_in_time

      model_path 'fog/aws/models/rds'
      model       :server
      collection  :servers
      model       :snapshot
      collection  :snapshots
      model       :parameter_group
      collection  :parameter_groups

      model       :parameter
      collection  :parameters

      model       :security_group
      collection  :security_groups

      class Mock

        def initialize(options={})
          Fog::Mock.not_implemented
        end

      end

      class Real

        # Initialize connection to ELB
        #
        # ==== Notes
        # options parameter must include values for :aws_access_key_id and
        # :aws_secret_access_key in order to create a connection
        #
        # ==== Examples
        #   elb = ELB.new(
        #    :aws_access_key_id => your_aws_access_key_id,
        #    :aws_secret_access_key => your_aws_secret_access_key
        #   )
        #
        # ==== Parameters
        # * options<~Hash> - config arguments for connection.  Defaults to {}.
        #   * region<~String> - optional region to use, in ['eu-west-1', 'us-east-1', 'us-west-1'i, 'ap-southeast-1']
        #
        # ==== Returns
        # * ELB object with connection to AWS.
        def initialize(options={})
          @aws_access_key_id      = options[:aws_access_key_id]
          @aws_secret_access_key  = options[:aws_secret_access_key]
          @hmac = Fog::HMAC.new('sha256', @aws_secret_access_key)

          options[:region] ||= 'us-east-1'
          @host = options[:host] || case options[:region]
          when 'ap-northeast-1'
            'rds.ap-northeast-1.amazonaws.com'
          when 'ap-southeast-1'
            'rds.ap-southeast-1.amazonaws.com'
          when 'eu-west-1'
            'rds.eu-west-1.amazonaws.com'
          when 'us-east-1'
            'rds.us-east-1.amazonaws.com'
          when 'us-west-1'
            'rds.us-west-1.amazonaws.com'
          else
            raise ArgumentError, "Unknown region: #{options[:region].inspect}"
          end
          @path       = options[:path]      || '/'
          @port       = options[:port]      || 443
          @scheme     = options[:scheme]    || 'https'
          @connection = Fog::Connection.new("#{@scheme}://#{@host}:#{@port}#{@path}", options[:persistent])
        end

        def reload
          @connection.reset
        end

        private

        def request(params)
          idempotent  = params.delete(:idempotent)
          parser      = params.delete(:parser)

          body = Fog::AWS.signed_params(
            params,
            {
              :aws_access_key_id  => @aws_access_key_id,
              :hmac               => @hmac,
              :host               => @host,
              :path               => @path,
              :port               => @port,
              :version            => '2010-07-28'
            }
          )

          begin
            response = @connection.request({
              :body       => body,
              :expects    => 200,
              :headers    => { 'Content-Type' => 'application/x-www-form-urlencoded' },
              :idempotent => idempotent,
              :host       => @host,
              :method     => 'POST',
              :parser     => parser
            })
          rescue Excon::Errors::HTTPStatusError => error
            if match = error.message.match(/<Code>(.*)<\/Code>[\s\\\w]+<Message>(.*)<\/Message>/m)
              case match[1].split('.').last
              when 'DBInstanceNotFound', 'DBParameterGroupNotFound', 'DBSnapshotNotFound', 'DBSecurityGroupNotFound'
                raise Fog::AWS::RDS::NotFound.slurp(error, match[2])
              when 'DBParameterGroupAlreadyExists'
                raise Fog::AWS::RDS::IdentifierTaken.slurp(error, match[2])
              else
                raise
              end
            else
              raise
            end
          end

          response
        end

      end
    end
  end
end
