require "libreconv/version"
require "uri"
require "net/http"
require "tmpdir"
require "spoon"

module Libreconv
  def self.convert(source, target, soffice_command = nil, convert_to = nil, opts = {})
    Converter.new(source, target, soffice_command, convert_to, opts).convert
  end

  class TimeoutError < ::Timeout::Error
  end

  class Converter
    attr_accessor :soffice_command

    def initialize(source, target, soffice_command = nil, convert_to = nil,
      timeout: 180,
      thread_id: nil,
      raise_timeout_error: false
    )
      @source = source
      @target = target
      @soffice_command = soffice_command
      @convert_to = convert_to || "pdf"

      @current_thread_id = thread_id
      @timeout_command = nil
      @timeout = (timeout || 180).to_s
      @raise_timeout_error = raise_timeout_error

      determine_soffice_command
      determine_timeout_command
      check_source_type

      unless @soffice_command && File.exists?(@soffice_command)
        raise IOError, "Can't find Libreoffice or Openoffice executable."
      end

      unless @timeout_command && File.exists?(@timeout_command)
        raise IOError, "Can't find Timeout executable."
      end
    end

    def convert
      orig_stdout = $stdout.clone
      $stdout.reopen File.new('/dev/null', 'w')
      Dir.mktmpdir { |target_path|
        cmd = [@timeout_command, @timeout, @soffice_command, "--headless", "--convert-to", @convert_to, @source, "--outdir", target_path, user_installation_env].compact
        pid = Spoon.spawnp(*cmd)
        Process.waitpid(pid)
        $stdout.reopen orig_stdout
        if @raise_timeout_error && !$?.nil? && [124, 137].include?($?.exitstatus)
          raise ::Libreconv::TimeoutError, "Convert program is timeout."
        end

        target_tmp_file = "#{target_path}/#{File.basename(@source, ".*")}.#{File.basename(@convert_to, ":*")}"
        FileUtils.cp target_tmp_file, @target
      }
    end

    private

    def determine_soffice_command
      unless @soffice_command
        @soffice_command ||= which("soffice")
        @soffice_command ||= which("soffice.bin")
      end
    end

    def determine_timeout_command
      return unless which('timeout')
      @timeout_command = which('timeout')
    end

    def which(cmd)
      exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
      ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
        exts.each do |ext|
          exe = File.join(path, "#{cmd}#{ext}")
          return exe if File.executable? exe
        end
      end

      return nil
    end

    def check_source_type
      return if File.exists?(@source) && !File.directory?(@source) #file
      return if URI(@source).scheme == "http" && Net::HTTP.get_response(URI(@source)).is_a?(Net::HTTPSuccess) #http
      return if URI(@source).scheme == "https" && Net::HTTP.get_response(URI(@source)).is_a?(Net::HTTPSuccess) #https
      raise IOError, "Source (#{@source}) is neither a file nor an URL."
    end

    def user_installation_env
      return nil if @current_thread_id.nil?
      "-env:UserInstallation=file://#{Dir.tmpdir}/libreconv_#{@current_thread_id}/"
    end
  end
end
