require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

# Helpers module
module Helpers
  # Helpers::Docker module
  module Docker
    class DockerNotReady < StandardError
      def initialize(endpoint, timeout)
        super <<-EOH
The Docker daemon did not become ready within #{timeout} seconds.
This most likely means that Docker failed to start.
Docker can fail to start if:

  - a configuration file is invalid
  - permissions are incorrect for the root directory of the docker runtime.

If this problem persists, check your service log files.
EOH
      end
    end

    def cli_args(spec)
      cli_line = ''
      spec.each_pair do |arg, value|
        case value
        when Array
          cli_line += value.map { |a| " -#{arg} " + a }.join
        when FalseClass
          cli_line += " -#{arg}=false"
        when Fixnum, Integer, String
          cli_line += " -#{arg} #{value}"
        when TrueClass
          cli_line += " -#{arg}=true"
        end
      end
      cli_line
    end

    def timeout
      node['docker']['docker_daemon_timeout']
    end

    # This is based upon wait_until_ready! from the opscode jenkins cookbook.
    #
    # Since the docker service returns immediately and the actual docker
    # process is started as a daemon, we block the Chef Client run until the
    # daemon is actually ready.
    #
    # This method will effectively "block" the current thread until the docker
    # daemon is ready
    #
    # @raise [DockerNotReady]
    #   if the Docker master does not respond within (+timeout+) seconds
    #
    def wait_until_ready!
      Timeout.timeout(timeout) do
        while true do
          result = shell_out('docker info')
          if not !Array(result.valid_exit_codes).include?(result.exitstatus)
            break
          end
          Chef::Log.debug("Docker daemon is not running - #{result.stdout}\n#{result.stderr}")
          sleep(0.5)
        end
      end
    rescue Timeout::Error
      raise DockerNotReady.new(timeout)
    end

    # the Error message to display if a command times out. Subclasses
    # may want to override this to provide more details on the timeout.
    def command_timeout_error_message
      <<-EOM

Command timed out:
#{cmd}

EOM
    end

    # Runs a docker command. Does not raise exception on non-zero exit code.
    def docker_cmd(cmd, timeout = new_resource.cmd_timeout)
      execute_cmd('docker ' + cmd, timeout)
    end

    # Executes the given command with the specified timeout. Does not raise an
    # exception on a non-zero exit code.
    def execute_cmd(cmd, timeout = new_resource.cmd_timeout)
      Chef::Log.debug('Executing: ' + cmd)
      begin
        shell_out(cmd, :timeout => timeout)
      rescue Mixlib::ShellOut::CommandTimeout
        raise CommandTimeout, command_timeout_error_message
      end
    end
  end
end
