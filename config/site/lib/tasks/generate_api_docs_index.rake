namespace :site do
  desc "Generate API docs search index"
  task :generate_api_docs_index do
    require "nokogiri"
    require "json"
    
    def extract_content(file_path)
      content = File.read(file_path)
      doc = Nokogiri::HTML(content)
      
      # Remove script and style elements
      doc.css('script, style').remove
      
      # Get the main content
      main_content = doc.css('#main').text
      
      # Clean up the text
      main_content.gsub!(/\s+/, ' ').strip
      
      # Get the title
      title = doc.css('title').text.strip
      title = title.split(' - ').first if title.include?(' - ')
      
      return title, main_content
    end
    
    def process_directory(dir)
      docs = []
      Dir.glob(File.join(dir, '**', '*.html')).each do |file|
        next if file.include?('/css/') || file.include?('/js/')
        next if %w[frames.html file_list.html class_list.html method_list.html].include?(File.basename(file))
        
        begin
          title, content = extract_content(file)
          relative_path = file.sub(Dir.pwd + '/_site', '')
          
          docs << {
            "title" => title,
            "url" => relative_path,
            "content" => content
          }
        rescue => e
          puts "Error processing #{file}: #{e.message}"
        end
      end
      docs
    end
    
    # Process all doc versions
    docs_dir = File.join(Dir.pwd, '_site/docs')
    all_docs = []
    
    Dir.entries(docs_dir).each do |version|
      next if version.start_with?('.')
      version_dir = File.join(docs_dir, version)
      next unless File.directory?(version_dir)
      
      docs = process_directory(version_dir)
      docs.each do |doc|
        doc["title"] = "API Documentation - #{version} - #{doc["title"]}"
      end
      all_docs.concat(docs)
    end
    
    # Write to data file
    FileUtils.mkdir_p 'src/_data'
    File.write('src/_data/api_docs.json', JSON.pretty_generate(all_docs))
  end
end