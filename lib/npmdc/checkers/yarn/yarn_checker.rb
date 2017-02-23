require 'pty'
require 'npmdc/checkers/yarn/yarn_installation_checker'

module Npmdc
  class YarnChecker
    extend Forwardable
    include Npmdc::Errors

    attr_reader :types, :formatter, :path, :path_to_yarn

    delegate [
      :output, :error_output, :dep_output,
      :check_start_output, :check_finish_output
    ] => :formatter

    def initialize(types:, formatter:, path:, path_to_yarn:)
      @types = types
      @formatter = formatter
      @path = path
      @path_to_yarn = path_to_yarn

      @errors = []
      @warnings = []
    end

    def check
      check_yarn_is_installed
      check_directory_exists(path)
      package_json_path = check_package_json_exists(path)
      package_json_data = try_to_parse_package_json(package_json_path)
      check_modules_directory(path)

      yarn_check

      handle_no_yarn_lock_error
      handle_missed_dependency_error

      output_success(count_packages(package_json_data))
    end

    private

    def check_yarn_is_installed
      YarnInstallationChecker.new(yarn_command).check_yarn_is_installed
    end

    def yarn_command
      @yarn_command ||=
        if path_to_yarn && path_to_yarn != ''
          File.join(path_to_yarn, 'yarn')
        else
          'yarn'
        end
    end

    def check_directory_exists(path)
      raise(WrongPathError, directory: path) unless Dir.exist?(path)
    end

    def check_package_json_exists(path)
      package_json_path = File.join(path, 'package.json')
      if File.file?(package_json_path)
        package_json_path
      else
        raise(MissedPackageError, directory: path)
      end
    end

    def try_to_parse_package_json(package_json_path)
      JSON.parse(File.read(package_json_path))
    rescue JSON::ParserError
      raise(JsonParseError, path: package_json_path)
    end

    def check_modules_directory(path)
      modules_directory = File.join(path, 'node_modules')
      if Dir.exist?(modules_directory)
        modules_directory
      else
        raise(NoNodeModulesError, path: path, manager: 'yarn')
      end
    end


    def yarn_check
      # yarn doesn't support separate check for dependencies and devDependencies yet
      # so ignore types and check all dependencies for now
      check_start_output('all dependencies via yarn check')

      cmd = "cd #{path} && #{yarn_command} check --json"
      puts cmd
      begin
        PTY.spawn(cmd) do |out, _in, process|
          begin
          puts out
          out.each do |line|
            puts line
            line = JSON.parse(line)
            type = line['type']
            data = line['data']
            case type
            when 'error'
              dep_output(data, :failure)
              @errors << data
            when 'warning'
              dep_output(data, :warn)
              @warnings << data
            when 'success'
              dep_output(data, :success)
            when 'activityTick'
              dep_output(data['name'], :success)
            end
          end
          rescue Errno::EIO
            puts "Errno:EIO error, but this probably just means " +
            "that the process has finished giving output"
          ensure
            Process.wait process
          end
        end
      rescue PTY::ChildExited
        puts "The child process exited!"
      end

      check_finish_output
    end

    def handle_no_yarn_lock_error
      if @errors == ["No lockfile in this directory. Run `yarn install` to generate one."]
        raise(NoYarnLockFileError)
      end
    end

    def handle_missed_dependency_error
      raise(MissedDependencyError, dependencies: @errors, manager: 'yarn') unless @errors.empty?
    end

    def output_success(packages_count)
      result_stats = "Checked #{packages_count} packages. Warnings: #{@warnings.count}. Errors: 0. Everything is ok."
      output(result_stats, :success)
    end

    def count_packages(package_json_data)
      dependencies = package_json_data['dependencies']
      dev_dependencies = package_json_data['devDependencies']
      dependencies_count = dependencies ? dependencies.count : 0
      dev_dependencies_count = dev_dependencies ? dev_dependencies.count : 0
      dependencies_count + dev_dependencies_count
    end
  end
end
