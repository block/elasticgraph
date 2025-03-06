module Jekyll
  class IncludeFileTag < Liquid::Tag
    def initialize(tag_name, path, tokens)
      super
      @path = path.strip
    end

    def render(context)
      site = context.registers[:site]
      
      # Convert the relative path to absolute
      source_path = site.source
      file_path = File.join(source_path, @path.gsub(/^\//, ''))
      
      # If the file doesn't exist in the source directory, check the _site directory
      unless File.exist?(file_path)
        file_path = File.join(site.dest, @path.gsub(/^\//, ''))
      end
      
      if File.exist?(file_path)
        File.read(file_path)
      else
        "File not found: #{@path}"
      end
    end
  end
end

Liquid::Template.register_tag('include_file', Jekyll::IncludeFileTag)