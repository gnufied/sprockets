require 'sprockets/asset_pathname'
require 'sprockets/concatenated_asset'
require 'sprockets/errors'
require 'sprockets/static_asset'
require 'pathname'

module Sprockets
  class EnvironmentIndex
    include Server, Processing, StaticCompilation

    attr_reader :logger, :context_class

    def initialize(environment, trail, static_root)
      @logger         = environment.logger
      @context_class  = environment.context_class

      @trail   = trail.index
      @assets  = {}
      @entries = {}

      @static_root = static_root ? Pathname.new(static_root) : nil

      @mime_types = environment.mime_types
      @engines    = environment.engines
      @filters    = environment.filters
      @formats    = environment.formats
    end

    def root
      @trail.root
    end

    def paths
      @trail.paths
    end

    def extensions
      @trail.extensions
    end

    def index
      self
    end

    def resolve(logical_path, options = {})
      if block_given?
        @trail.find(logical_path.to_s, logical_index_path(logical_path), options) do |path|
          yield Pathname.new(path)
        end
      else
        resolve(logical_path, options) do |pathname|
          return pathname
        end
        raise FileNotFound, "couldn't find file '#{logical_path}'"
      end
    end

    def find_asset(logical_path)
      logical_path     = logical_path.to_s.sub(/^\//, '')
      logical_pathname = Pathname.new(logical_path)

      if @assets.key?(logical_path)
        @assets[logical_path]
      else
        @assets[logical_path] = find_asset_in_static_root(logical_pathname) ||
          find_asset_in_path(logical_pathname)
      end
    end
    alias_method :[], :find_asset

    protected
      def expire_index!
        raise TypeError, "can't modify immutable index"
      end

      def find_asset_in_path(logical_path)
        if fingerprint = path_fingerprint(logical_path)
          pathname = resolve(logical_path.to_s.sub("-#{fingerprint}", ''))
        else
          pathname = resolve(logical_path)
        end
      rescue FileNotFound
        nil
      else
        asset_pathname = AssetPathname.new(pathname, self)
        extension      = asset_pathname.format_extension ||
                         asset_pathname.engine_format_extension

        if formats(extension).any?
          logger.info "[Sprockets] #{logical_path} building"
          asset = ConcatenatedAsset.new(self, pathname)
        else
          asset = StaticAsset.new(self, pathname)
        end

        if fingerprint && fingerprint != asset.digest
          logger.error "[Sprockets] #{logical_path} #{fingerprint} nonexistent"
          asset = nil
        end

        asset
      end

    private
      def logical_index_path(logical_path)
        pathname = Pathname.new(logical_path)
        asset_pathname = AssetPathname.new(logical_path, self)

        if asset_pathname.basename_without_extensions.to_s == 'index'
          logical_path
        else
          basename = "#{asset_pathname.basename_without_extensions}/index#{asset_pathname.extensions.join}"
          pathname.dirname.to_s == '.' ? basename : pathname.dirname.join(basename).to_s
        end
      end
  end
end
