
require 'csv'
require 'json'
require 'open3'
require 'open-uri'

require 'nokogiri'

require_relative 'lib/constants'


# Enclose CollectionBuilder-related tasks in a namespaced called "cb", to be
# executed using the convention: `rake cb:{task_name}`
namespace :cb do

  ###############################################################################
  # deploy
  ###############################################################################

  desc "Build site with production env"
  task :deploy do
    ENV['JEKYLL_ENV'] = "production"
    sh "jekyll build --config _config.yml,_config.production.yml"
  end


  ###############################################################################
  # serve
  ###############################################################################

  desc "Run the local web server"
  task :serve, [:env] do |t, args|
    args.with_defaults(
      :env => "DEVELOPMENT"
    )
    assert_env_arg_is_valid args.env, [ 'DEVELOPMENT', 'PRODUCTION_PREVIEW' ]
    env = args.env.to_sym
    config_filenames = $ENV_CONFIG_FILENAMES_MAP[env]
    sh "jekyll s --config #{config_filenames.join(',')} -H 0.0.0.0"
  end


  ###############################################################################
  # read_collections_metadata
  ###############################################################################

  desc "Read and save metadata from the configured collections websites"
  task :read_collections_metadata do
    config = load_config :DEVELOPMENT

    # Collect configured collection URLs.
    urls = config[:collections_config].map { |x| x['homepage_url'] }

    # Attempt to retrieve the required JSON-LD data from each collection home page.
    url_metadata_map = Hash.new (Hash.new {})
    urls.each do |url|
      announce "Retrieving metadata from: #{url}"
      begin
        res = URI.open url
      rescue
        puts 'FAILED - Could not open the URL'
        next
      end

      begin
        doc = Nokogiri.parse res.read
      rescue
        puts 'FAILED - Response is not valid HTML'
        next
      end

      elements = doc.css('script[type="application/ld+json"]')
      if elements.length == 0
        puts 'FAILED - Response does not contain a JSON-LD script tag'
        next
      end
      if elements.length > 1
        puts 'WARNING - Reading only the first of multiple JSON-LD script tags'
      end
      script_tag = elements[0]

      begin
        data = JSON.parse(script_tag.text)
      rescue
        puts "FAILED - JSON-LD script tag contents is not valid JSON"
        next
      end

      collection_metadata = {}
      $COLLECTION_JSON_LD_METADATA_KEYS.each do |k|
        $stdout.write "#{k} => "
        if not data.has_key? k
          puts 'MISSING'
          next
        elsif data[k].length == 0
          puts 'EMPTY'
          next
        else
          value = data[k]
          collection_metadata[k] = value
          snippet = value.slice(0, 20)
          if value.length > 20
            snippet += '...'
          end
          puts "\"#{snippet}\""
        end
      end

      # Write the data to the collections metadata file.
      if collection_metadata.length == 0
        next
      end
      collection_data_dir = get_ensure_collection_data_dir(url)
      output_path = File.join([collection_data_dir, 'collection-metadata.json'])
      File.open(output_path, 'w') do |fh|
        fh.write(JSON.dump collection_metadata)
      end
      puts "Wrote: #{output_path}"
    end
  end


  ###############################################################################
  # download_collections_objects_metadata
  ###############################################################################

  desc "Download the object metadata files for each collection"
  task :download_collections_objects_metadata do
    config = load_config :DEVELOPMENT

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    collection_urls.each do |collection_url|
      url = collection_url.delete_suffix('/') + '/' \
            + $COLLECTIONBUILDER_JSON_METADATA_PATH.delete_prefix('/')
      announce "Downloading objects metadata from: #{url}"
      begin
        res = URI.open url
      rescue
        puts 'FAILED - Could not open the URL'
        next
      end

      # Parse the response as JSON to check that it's valid.
      data = res.read
      begin
        JSON.parse data
      rescue
        puts "FAILED - Response is not valid JSON"
        next
      end

      collection_data_dir = get_ensure_collection_data_dir(collection_url)
      output_path = File.join([collection_data_dir, "objects-metadata.json"])
      File.open(output_path, 'w') do |f|
        num_bytes = f.write(data)
        puts "Wrote #{num_bytes} bytes to: #{output_path}"
      end
    end
  end


  ###############################################################################
  # download_collections_pdfs
  ###############################################################################

  desc "Download collections PDFs for text extraction"
  task :download_collections_pdfs do
    config = load_config :DEVELOPMENT

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    collection_urls.each do |collection_url|
      collection_data_dir = get_ensure_collection_data_dir(collection_url)
      collection_objects_metadata_path = File.join(
        [ collection_data_dir, "objects-metadata.json"]
      )
      objects_metadata = JSON.load File.open(collection_objects_metadata_path, 'rb')
      pdf_objects_metadata = objects_metadata['objects'].select do |object_metadata|
        object_metadata['format'] == $APPLICATION_PDF
      end

      if pdf_objects_metadata.length == 0
        announce "#{collection_objects_metadata_path} contains no PDFs - skipping"
        next
      end

      announce "Downloading objects from: #{collection_url}"
      pdfs_dir = get_ensure_collection_pdfs_dir(collection_url)
      pdf_objects_metadata.each do |pdf_object_metadata|
        url = pdf_object_metadata['object_download']
        $stdout.write "Downloading: #{url} - "
        begin
          res = URI.open url
        rescue
          puts 'FAILED - Could not open the URL'
          next
        end
        output_path = File.join([pdfs_dir, filename_escape(url)])
        File.open(output_path, 'wb') do |f|
          f.write(res.read)
        end
        puts 'DONE'
      end
    end
  end


  ###############################################################################
  # extract_pdf_text
  ###############################################################################

  desc "Extract the text from PDF collection objects"
  task :extract_pdf_text do
    config = load_config :DEVELOPMENT

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    collection_urls.each do |collection_url|
      input_dir = get_ensure_collection_pdfs_dir(collection_url)
      output_dir = get_ensure_collection_extracted_pdf_text_dir(collection_url)

      num_items = 0
      input_paths = Dir.glob(File.join([input_dir, '*']))

      if input_paths.length == 0
        announce "#{input_dir} contains no PDFs - skipping"
        next
      end

      announce "Extracting text from PDFs in: #{input_dir}"
      input_paths.each do |input_path|
        $stdout.write "\nExtracting text from: #{input_path} - "
        output_path = File.join([output_dir, "#{File.basename(input_path)}.txt"])
        stdout_stderr, status = Open3.capture2e(
          "pdftotext -enc UTF-8 -eol unix -nopgbrk #{input_path} #{output_path}"
        )
        if status.success?
          puts 'DONE'
          puts "Wrote: #{output_path}"
        else
          puts "ERROR\n#{stdout_stderr}"
        end
      end
    end
  end


  ###############################################################################
  # generate_search_index_data
  ###############################################################################

  desc "Generate the file that we'll use to populate the Elasticsearch index via the Bulk API"
  task :generate_search_index_data, [:env] do |t, args|
    args.with_defaults(
      :env => "DEVELOPMENT"
    )
    assert_env_arg_is_valid args.env
    env = args.env.to_sym

    config = load_config env

    # Get the development config for local directory info.
    dev_config = load_config :DEVELOPMENT

    # Create a search config <fieldName> => <configDict> map.
    field_config_map = {}
    dev_config[:search_config].each do |row|
      field_config_map[row['field']] = row
    end

    output_dir = dev_config[:elasticsearch_dir]
    $ensure_dir_exists.call output_dir
    output_path = File.join([output_dir, $ES_BULK_DATA_FILENAME])
    output_file = File.open(output_path, mode: "w")
    index_name = dev_config[:elasticsearch_index]
    num_items = 0
    dev_config[:metadata].each do |item|
      # Remove any fields with an empty value.
      item.delete_if { |k, v| v.nil? }

      # Split each multi-valued field value into a list of values.
      item.each do |k, v|
        if field_config_map.has_key? k and field_config_map[k]['multi-valued'] == "true"
          item[k] = (v or "").split(";").map { |s| s.strip }
        end
      end

      item['url'] = "#{config[:collection_url]}/items/#{item['objectid']}.html"
      item['collectionUrl'] = config[:collection_url]
      item['collectionTitle'] = config[:collection_title]

      # Add the thumbnail image URL.
      if env == :DEVELOPMENT
        item['thumbnailContentUrl'] = "#{File.join(config[:thumb_images_dir], item['objectid'])}_th.jpg"
      else
        item['thumbnailContentUrl'] = "#{config[:remote_thumb_images_url]}/#{item['objectid']}_th.jpg"
      end

      # If a extracted text file exists for the item, add the content of that file to the item
      # as the "full_text" property.
      item_text_path = File.join([dev_config[:extracted_pdf_text_dir], "#{item['objectid']}.txt"])
      if File::exists? item_text_path
        full_text = File.read(item_text_path, mode: "r", encoding: "utf-8")
        item['full_text'] = full_text
      end

      # Write the action_and_meta_data line.
      doc_id = item['objectid']
      output_file.write("{\"index\": {\"_index\": \"#{index_name}\", \"_id\": \"#{doc_id}\"}}\n")

      # Write the source line.
      output_file.write("#{JSON.dump(item.to_hash)}\n")

      num_items += 1
    end

    output_file.close

    puts "Wrote #{num_items} items to: #{output_path}"
  end


  ###############################################################################
  # generate_search_index_settings
  ###############################################################################

  # Generate a file that comprises the Mapping settings for the Elasticsearch index
  # from the configuration specified in _data/config.search.yml
  # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html

  desc "Generate the settings file that we'll use to create the Elasticsearch index"
  task :generate_search_index_settings do
    TEXT_FIELD_DEF_KEYS = [ 'field' ]
    BOOL_FIELD_DEF_KEYS = [ 'index', 'display', 'facet', 'multi-valued' ]
    VALID_FIELD_DEF_KEYS = TEXT_FIELD_DEF_KEYS.dup.concat BOOL_FIELD_DEF_KEYS
    INDEX_SETTINGS_TEMPLATE = {
      mappings: {
        dynamic_templates: [
          {
            store_as_unindexed_text: {
              match_mapping_type: "*",
              mapping: {
                type: "text",
                index: false
              }
            }
          }
        ],
        properties: {
          # Define the set of static properties.
          objectid: {
            type: "text",
            index: false
          },
          url: {
            type: "text",
            index: false,
          },
          thumbnailContentUrl: {
            type: "text",
            index: false,
          },
          collectionTitle: {
            type: "text",
            index: false,
          },
          collectionUrl: {
            type: "text",
            index: false,
          }
        }
      }
    }

    def assert_field_def_is_valid field_def
      # Assert that the field definition is valid.
      keys = field_def.to_hash.keys

      missing_keys = VALID_FIELD_DEF_KEYS.reject { |k| keys.include? k }
      extra_keys = keys.reject { |k| VALID_FIELD_DEF_KEYS.include? k }
      if !missing_keys.empty? or !extra_keys.empty?
        msg = "The field definition: #{field_def}"
        if !missing_keys.empty?
          msg = "#{msg}\nis missing the required keys: #{missing_keys}"
        end
        if !extra_keys.empty?
          msg = "#{msg}\nincludes the unexpected keys: #{extra_keys}"
        end
        raise msg
      end

      invalid_bool_value_keys = BOOL_FIELD_DEF_KEYS.reject { |k| ['true', 'false'].include? field_def[k] }
      if !invalid_bool_value_keys.empty?
        raise "Expected true/false value for: #{invalid_bool_value_keys.join(", ")}"
      end

      if field_def['index'] == "false" and
        (field_def['facet'] == "true" or field_def['multi-valued'] == "true")
        raise "Field (#{field_def['field']}) has index=false but other index-related "\
              "fields (e.g. facet, multi-valued) specified as true"
      end

      if field_def['multi-valued'] == "true" and field_def['facet'] != "true"
        raise "If field (#{field_def['field']}) specifies multi-valued=true, it "\
              "also needs to specify facet=true"
      end
    end

    def convert_field_def_bools field_def
      # Do an in-place conversion of the bool strings to python bool values.
      BOOL_FIELD_DEF_KEYS.each do |k|
        field_def[k] = field_def[k] == "true"
      end
    end

    def get_mapping field_def
      # Return an ES mapping configuration object for the specified field definition.
      mapping = {
        type: "text"
      }
      if field_def['facet']
        mapping['fields'] = {
          raw: {
            type: "keyword"
          }
        }
      end
      return mapping
    end

    # Main block
    config = load_config :DEVELOPMENT

    index_settings = INDEX_SETTINGS_TEMPLATE.dup

    # Add the _meta mapping field with information about the index itself.
    index_settings[:mappings]['_meta'] = {
      :title => config[:collection_title],
      :description => config[:collection_description],
    }

    config[:search_config].each do |field_def|
      assert_field_def_is_valid(field_def)
      convert_field_def_bools(field_def)
      if field_def['index']
        index_settings[:mappings][:properties][field_def['field']] = get_mapping(field_def)
      end
    end

    output_dir = config[:elasticsearch_dir]
    $ensure_dir_exists.call output_dir
    output_path = File.join([output_dir, $ES_INDEX_SETTINGS_FILENAME])
    File.open(output_path, mode: 'w') do |f|
      f.write(JSON.pretty_generate(index_settings))
    end
    puts "Wrote: #{output_path}"
  end

# Close the namespace.
end
