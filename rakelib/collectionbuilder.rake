
require 'csv'
require 'digest'
require 'json'
require 'open3'
require 'open-uri'

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
  # generate_collections_metadata
  ###############################################################################

  desc "Generate metadata for each collection from local config and remote JSON-LD"
  task :generate_collections_metadata do
    collections_config = load_config(:DEVELOPMENT)[:collections_config]

    # Attempt to retrieve the required JSON-LD data from each collection home page.
    url_metadata_map = Hash.new { |h,k| h[k] = {} }
    collections_config.each do |collection_config|
      url = collection_config['homepage_url']
      announce "Generating metadata for collection #{url}"

      # Use the collection config as the initial metadata value.
      collection_metadata = collection_config.to_hash

      # Create a list of mapped JSON-LD keys that we can use to fill in empty fields.
      json_ld_key_map = $JSON_LD_COLLECTION_METADATA_KEY_MAP.select {
        |k, v| collection_metadata[v] == nil
      }

      if json_ld_key_map.length > 0
        # Attempt to fetch the parsed JSON-LD object.
        json_ld = fetch_json_ld(url) or {}

        if json_ld != nil
          # Populate the empty fields using the JSON-LD data.
          json_ld_key_map.each do |json_ld_k, metadata_k|
            value = json_ld[json_ld_k]
            if not value.nil? and not value.empty?
              collection_metadata[metadata_k] = value
              puts "Retrieved #{metadata_k} from JSON-LD as: \"#{value}\""
            end
          end
        end
      end

      # Prompt for any missing values that we can't automatically derive.
      $REQUIRED_COLLECTION_METADATA_KEYS.each do |k|
        if collection_metadata[k] == nil
          $stdout.write "Could not determine a value for '#{k}' - " \
                        "please provide one here: "
          collection_metadata[k] = STDIN.gets.chomp
        end
      end

      collection_data_dir = get_ensure_collection_data_dir(url)
      output_path = get_collection_metadata_path url
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
      output_path = File.join(
        [collection_data_dir, $COLLECTION_OBJECTS_METADATA_FILENAME]
      )
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
      objects_metadata = read_collection_objects_metadata collection_url
      pdf_objects_metadata = objects_metadata.select do |object_metadata|
        object_metadata['format'] == $APPLICATION_PDF
      end

      if pdf_objects_metadata.length == 0
        announce "#{get_collection_objects_metadata_path collection_url} contains "\
                 "no PDFs - skipping"
        next
      end

      announce "Downloading PDFs from: #{collection_url}"
      pdfs_dir = get_ensure_collection_pdfs_dir(collection_url)
      #pdf_objects_metadata.each do |pdf_object_metadata|
      pdf_objects_metadata.slice(0, 4).each do |pdf_object_metadata|
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
  # generate_search_config
  ###############################################################################

  desc "Create an initial search config from the superset of all object fields"
  task :generate_search_config do
    config = load_config :DEVELOPMENT

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    # Define map that will be used to generate the search config file.
    # Each config hash will have the keys: display, facet, multi-valued.
    collection_url_field_config_map = {}

    collection_urls.each do |collection_url|
      announce "Analyzing object metadata for collection: #{collection_url}"
      objects_metadata = read_collection_objects_metadata collection_url

      field_config_map = collection_url_field_config_map[collection_url] = {}

      # Collect the set of unique values for each non-excluded field.
      field_uniq_values_map = Hash.new { |h,k| h[k] = Set[] }
      excluded_fields = Set[]

      objects_metadata.each do |object_metadata|
        object_metadata.each do |field,value|
          if $SEARCH_CONFIG_EXCLUDED_FIELDS.include? field
            excluded_fields.add(field)
            next
          end
          # Strip the value and add it to the uniq values set for this field.
          field_uniq_values_map[field].add value.strip
        end
      end
      if excluded_fields
        puts "Excluded the following field(s) per the SEARCH_CONFIG_EXCLUDED_FIELDS "\
             "setting:"
        puts excluded_fields.sort().map { |x| "  #{x}" }.join("\n")
      end

      # Process the collected field values to determine which should be included in
      # the search config and with what characteristics.
      num_objects = objects_metadata.length
      field_uniq_values_map.each do |field,values|
        # Ignore fields with no, non-empty values.
        if values.empty? or values.length == 1 and values.first == ''
          puts "Ignoring field (#{field}) for which no object specifies a value."
          next
        end
        # Consider the field to be facet-able if the number of unique values is less
        # than 100 and the cardinality / total-num-objects ratio is less than 0.5
        facet = values.length < 100 and values.length < num_objects * 0.5
        # Take the presence of a semicolon in at least 5% of the values to indicate
        # that the field is multi-valued.
        num_values_with_semi = values.map { |x| x.include?(';') ? 1 : 0 }.sum
        is_multi_valued = num_values_with_semi >= values.length * 0.05
        field_config_map[field] = {
          'display' => $SEARCH_CONFIG_DEFAULT_DISPLAY_FIELDS.include?(field),
          'facet' => facet,
          'multi-valued' => is_multi_valued,
          'index' => true
        }
      end
    end

    # Combine the collection-specific search configs into a single config.
    search_config = {}
    collection_url_field_config_map.each do |collection_url,field_config_map|
      field_config_map.each do |field, field_config|
        if not search_config.include? field
          search_config[field] = field_config
          next
        end
        search_config[field]['index'] |= field_config['index']
        search_config[field]['multi-valued'] |= field_config['multi-valued']
        search_config[field]['facet'] &= field_config['facet']
      end
    end

    # Always include full_text.
    search_config['full_text'] = {
      'display' => false,
      'index' => true,
      'facet' => false,
      'multi-valued' => false
    }

    # Ensure that any multi-valued field is also faceted.
    search_config.values.each do |field_config|
      field_config['facet'] |= field_config['multi-valued']
    end

    # Write out the search config file.
    CSV.open($SEARCH_CONFIG_PATH, 'w') do |writer|
      writer << [ 'field', 'display', 'index', 'facet', 'multi-valued' ]
      # TODO - probably sort this output in some desired display order.
      search_config.each do |k,config|
        writer << [ k, config['display'], config['index'], config['facet'],
                    config['multi-valued'] ]
      end
    end
    announce 'Done'
    puts "Wrote #{search_config.length} fields to: #{$SEARCH_CONFIG_PATH}"
    puts "Please inspect and edit this file to customize the search index "\
         "configuration and web application UI."
  end

  ###############################################################################
  # generate_collection_search_index_data
  ###############################################################################

  desc "Generate the file that we'll use to populate the Elasticsearch index via "\
       "the Bulk API"
  task :generate_collection_search_index_data, [:env, :collection_url] do |t, args|
    args.with_defaults(
      :env => "DEVELOPMENT"
    )
    assert_env_arg_is_valid args.env
    env = args.env.to_sym
    collection_url = args.collection_url

    config = load_config env

    # Create a search config <fieldName> => <configDict> map.
    field_search_config_map = read_search_config

    # Get collection-specific metadata and directories.
    collection_metadata = read_collection_metadata collection_url
    objects_metadata = read_collection_objects_metadata collection_url
    extracted_text_dir = get_ensure_collection_extracted_pdf_text_dir collection_url
    output_dir = get_ensure_collection_elasticsearch_dir(collection_url)

    output_path = File.join([output_dir, $ES_BULK_DATA_FILENAME])
    output_file = File.open(output_path, mode: "w")
    index_name = collection_url_to_elasticsearch_index collection_url

    num_items = 0
    # Iterate through the object metadatas.
    objects_metadata.each do |item|
      # Remove any fields with an empty value.
      item.delete_if { |k, v| v.nil? }

      # Split each multi-valued field value into a list of values.
      item.each do |k, v|
        if field_search_config_map.has_key? k \
          and field_search_config_map[k]['multi-valued'] == "true"
          item[k] = (v or "").split(";").map { |s| s.strip }
        end
      end

      item['url'] = item['reference_url']
      item['collectionUrl'] = collection_url
      item['collectionTitle'] = collection_metadata['title']
      item['thumbnailContentUrl'] = item['object_thumb'] or item['image_thumb']

      # If a extracted text file exists for the item, add the content of that file to
      # the item as the "full_text" property.
      item_text_path = File.join(
        [ extracted_text_dir, "#{filename_escape item['object_download']}.txt" ]
      )
      if File::exists? item_text_path
        full_text = File.read(item_text_path, mode: "r", encoding: "utf-8")
        item['full_text'] = full_text
      end

      # Use the MD5 of the reference_url as the document ID.
      doc_id = Digest::MD5.hexdigest item['reference_url']

      # Write the action_and_meta_data line.
      output_file.write(
        "{\"index\": {\"_index\": \"#{index_name}\", \"_id\": \"#{doc_id}\"}}\n"
      )

      # Write the source line.
      output_file.write("#{JSON.dump(item.to_hash)}\n")

      num_items += 1
    end

    output_file.close

    puts "Wrote #{num_items} items to: #{output_path}"
  end


  ###############################################################################
  # generate_collections_search_index_data
  ###############################################################################

  desc "Generate the file that we'll use to populate the Elasticsearch index via "\
       "the Bulk API for all configured collections"
  task :generate_collections_search_index_data, [:env] do |t, args|
    args.with_defaults(
      :env => "DEVELOPMENT"
    )
    assert_env_arg_is_valid args.env

    config = load_config args.env.to_sym

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    collection_urls.each do |collection_url|
      Rake::Task['cb:generate_collection_search_index_data'].execute(
        Rake::TaskArguments.new([:env, :collection_url], [args.env, collection_url])
      )
    end
  end


  ###############################################################################
  # generate_collection_search_index_settings
  ###############################################################################

  # Generate a file that comprises the Mapping settings for the Elasticsearch index
  # from the configuration specified in _data/config.search.yml
  # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html

  desc "Generate the settings file that we'll use to create the Elasticsearch index"
  task :generate_collection_search_index_settings, [:collection_url] do |t, args|
    def assert_field_def_is_valid field_name, field_def
      # Assert that the field definition is valid.
      keys = field_def.to_hash.keys

      missing_keys = $VALID_FIELD_DEF_KEYS.reject { |k| keys.include? k }
      extra_keys = keys.reject { |k| $VALID_FIELD_DEF_KEYS.include? k }
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

      invalid_bool_value_keys = $BOOL_FIELD_DEF_KEYS.reject {
        |k| ['true', 'false'].include? field_def[k]
      }
      if !invalid_bool_value_keys.empty?
        raise "Expected true/false value for: #{invalid_bool_value_keys.join(", ")}"
      end

      if field_def['index'] == "false" and
        (field_def['facet'] == "true" or field_def['multi-valued'] == "true")
        raise "Field (#{field_name}) has index=false but other index-related "\
              "fields (e.g. facet, multi-valued) specified as true"
      end

      if field_def['multi-valued'] == "true" and field_def['facet'] != "true"
        raise "If field (#{field_def['field']}) specifies multi-valued=true, it "\
              "also needs to specify facet=true"
      end
    end

    def convert_field_def_bools field_def
      # Do an in-place conversion of the bool strings to python bool values.
      $BOOL_FIELD_DEF_KEYS.each do |k|
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

    # Read the collection metadata.
    collection_url = args.collection_url
    collection_metadata = read_collection_metadata collection_url

    index_settings = $INDEX_SETTINGS_TEMPLATE.dup

    # Add the _meta mapping field with information about the index itself.
    index_settings[:mappings]['_meta'] = {
      :title => collection_metadata['title'],
      :description => collection_metadata['description'],
    }

    field_search_config_map = read_search_config
    field_search_config_map.sort.each do |field_name, field_def|
      assert_field_def_is_valid(field_name, field_def)
      convert_field_def_bools(field_def)
      if field_def['index']
        index_settings[:mappings][:properties][field_name] = get_mapping(field_def)
      end
    end

    output_dir = get_ensure_collection_elasticsearch_dir collection_url
    output_path = File.join([output_dir, $ES_INDEX_SETTINGS_FILENAME])
    File.open(output_path, mode: 'w') do |f|
      f.write(JSON.pretty_generate(index_settings))
    end
    puts "Wrote: #{output_path}"
  end


  ###############################################################################
  # generate_collections_search_index_settings
  ###############################################################################

  desc "Generate the Elasticsearch index settings files for all configured collections"
  task :generate_collections_search_index_settings, [:env] do |t, args|
    args.with_defaults(
      :env => "DEVELOPMENT"
    )
    assert_env_arg_is_valid args.env

    config = load_config args.env.to_sym

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    collection_urls.each do |collection_url|
      Rake::Task['cb:generate_collection_search_index_settings'].execute(
        Rake::TaskArguments.new([:env, :collection_url], [args.env, collection_url])
      )
    end

  end

  ###############################################################################
  # create_collections_search_indices
  ###############################################################################

  desc "Create Elasticsearch indices all configured collections"
  task :create_collections_search_indices, [:env, :es_profile] do |t, args|
    args.with_defaults(
      :env => "DEVELOPMENT"
    )
    assert_env_arg_is_valid args.env

    config = load_config args.env.to_sym

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    collection_urls.each do |collection_url|
      index = collection_url_to_elasticsearch_index collection_url
      es_dir = get_ensure_collection_elasticsearch_dir collection_url
      settings_path = File.join([es_dir, $ES_INDEX_SETTINGS_FILENAME])
      begin
        Rake::Task['es:create_index'].execute(
          Rake::TaskArguments.new(
            [:profile, :index, :settings_path],
            [args.es_profile, index, settings_path]
          )
        )
      rescue SystemExit
        # Catch SystemExit to prevent any sub-task abort() from terminating this task.
      end
    end
  end


  ###############################################################################
  # load_collections_search_index_data
  ###############################################################################

  desc "Load data into Elasticsearch indices for all configured collections"
  task :load_collections_search_index_data, [:env, :es_profile] do |t, args|
    args.with_defaults(
      :env => "DEVELOPMENT"
    )
    assert_env_arg_is_valid args.env

    config = load_config args.env.to_sym

    # Collect configured collection URLs.
    collection_urls = config[:collections_config].map { |x| x['homepage_url'] }

    collection_urls.each do |collection_url|
      es_dir = get_ensure_collection_elasticsearch_dir collection_url
      datafile_path = File.join([es_dir, $ES_BULK_DATA_FILENAME])

      begin
        Rake::Task['es:load_bulk_data'].execute(
          Rake::TaskArguments.new(
            [:profile, :datafile_path],
            [args.es_profile, datafile_path]
          )
        )
      rescue SystemExit
        # Catch SystemExit to prevent any sub-task abort() from terminating this task.
      end
    end
  end


  ###############################################################################
  # build
  ###############################################################################

  desc "Execute all build steps required to go from a config-collection file to "\
       "fully-populated Elasticsearch index"
  task :build, [:env] do |t, args|
    args.with_defaults(
      :env => 'DEVELOPMENT'
    )
    assert_env_arg_is_valid args.env
    env = args.env.to_sym

    profile = $ENV_ES_PROFILE_MAP[env]

    banner_announce 'Reading JSON-LD encoded metadata from the collection homepage URLs'
    Rake::Task['cb:generate_collections_metadata'].invoke

    banner_announce 'Downloading collection object metadata files'
    Rake::Task['cb:download_collections_objects_metadata'].invoke

    banner_announce 'Generating the default search configuration'
    Rake::Task['cb:generate_search_config'].invoke

    banner_announce 'Downloading collection PDFs for text extraction'
    Rake::Task['cb:download_collections_pdfs'].invoke

    banner_announce 'Extracting text from downloaded PDFs'
    Rake::Task['cb:extract_pdf_text'].invoke

    banner_announce 'Generating the Elasticsearch index data files'
    Rake::Task['cb:generate_collections_search_index_data'].invoke

    banner_announce 'Generating the Elasticsearch index settings files'
    Rake::Task['cb:generate_collections_search_index_settings'].invoke

    # Check that the Elasticsearch instance is available and accessible.
    while ! elasticsearch_ready profile
      puts 'Waiting for Elasticsearch... Is it running?'
      sleep 2
    end

    # Create the directory index before the collection index so that the call
    # to create_index will automatically update the directory.
    banner_announce 'Create the directory index'
    begin
      Rake::Task['es:create_directory_index'].invoke profile
    rescue SystemExit
      # Catch SystemExit to prevent any sub-task abort() from terminating this task.
    end

    banner_announce 'Create a search index for each collection'
    Rake::Task['cb:create_collections_search_indices'].invoke profile

    banner_announce 'Load collection data into the search indices'
    Rake::Task['cb:load_collections_search_index_data'].invoke profile

    # TODO - maybe also enable daily snapshots

    banner_announce 'Search indices are loaded and ready!'
    # Generate sample index document and directory index URLs.
    config = $get_config_for_es_profile.call profile
    proto = config[:elasticsearch_protocol]
    host = config[:elasticsearch_host]
    port = config[:elasticsearch_port]
    es_url = "#{proto}://#{host}:#{port}"

    index_doc_url = "#{es_url}/#{config[:elasticsearch_index]}/_search?size=1"
    puts "To view a sample search index document, visit: #{index_doc_url}"

    directory_index_url = "#{es_url}/#{config[:elasticsearch_directory_index]}/_search"
    puts "To view the directory index, visit: #{directory_index_url}"

  end


  ###############################################################################
  # enable_daily_search_index_snapshots
  ###############################################################################

  desc "Enable daily Elasticsearch snapshots to be written to the \"#{$ES_DEFAULT_SNAPSHOT_REPOSITORY_BASE_PATH}\" directory of your Digital Ocean Space."
  task :enable_daily_search_index_snapshots, [:profile] do |t, args|
    # Check that the user has already completed the server-side configuration.
    if !prompt_user_for_confirmation "Did you already run the configure-s3-snapshots script on the Elasticsearch instance?"
      puts "Please see the README for instructions on how to run the configure-s3-snapshots script."
      exit 1
    end

    profile = args.profile

    config = $get_config_for_es_profile.call profile

    # Assert that the specified user is associated with a production config.
    if !config.has_key? :remote_objects_url
      puts "Please specify a production ES user"
    end

    # Get the Digital Ocean Space bucket value.
    bucket = parse_digitalocean_space_url(config[:remote_objects_url])[0]

    # Create the S3 snapshot repository.
    Rake::Task['es:create_snapshot_s3_repository'].invoke profile, bucket

    # Create the automatic snapshot policy.
    Rake::Task['es:create_snapshot_policy'].invoke profile

    # Manually execute the policy to test it.
    puts "Manually executing the snapshot policy to ensure that it works..."
    Rake::Task['es:execute_snapshot_policy'].invoke profile
  end

# Close the namespace.
end
