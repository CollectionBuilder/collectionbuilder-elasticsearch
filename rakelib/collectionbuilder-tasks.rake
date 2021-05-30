
require 'json'


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
  # extract_pdf_text
  ###############################################################################

  desc "Extract the text from PDF collection objects"
  task :extract_pdf_text do

    config = load_config :DEVELOPMENT
    output_dir = config[:extracted_pdf_text_dir]
    $ensure_dir_exists.call output_dir

    # Extract the text.
    num_items = 0
    Dir.glob(File.join([config[:objects_dir], "*.pdf"])).each do |filename|
      output_filename = File.join(
        [output_dir, "#{File.basename(filename, File.extname(filename))}.txt"]
      )
      system("pdftotext -enc UTF-8 -eol unix -nopgbrk #{filename} #{output_filename}")
      num_items += 1
    end
    puts "Extracted text from #{num_items} PDFs into: #{output_dir}"
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
