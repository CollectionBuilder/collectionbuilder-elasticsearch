
require 'json'

require 'aws-sdk-s3'


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
  # generate_derivatives
  ###############################################################################

  desc "Generate derivative image files from collection objects"
  task :generate_derivatives, [:thumbs_size, :small_size, :density, :missing, :im_executable] do |t, args|
    args.with_defaults(
      :thumbs_size => "300x300",
      :small_size => "800x800",
      :density => "90",
      :missing => "true",
      :im_executable => "magick",
    )

    config = load_config :DEVELOPMENT
    objects_dir = config[:objects_dir]
    thumb_images_dir = config[:thumb_images_dir]
    small_images_dir = config[:small_images_dir]

    # Ensure that the output directories exist.
    [thumb_images_dir, small_images_dir].each &$ensure_dir_exists

    EXTNAME_TYPE_MAP = {
      '.jpg' => :image,
      '.pdf' => :pdf
    }

    # Generate derivatives.
    Dir.glob(File.join([objects_dir, '*'])).each do |filename|
      # Ignore subdirectories.
      if File.directory? filename
        next
      end

      # Determine the file type and skip if unsupported.
      extname = File.extname(filename).downcase
      file_type = EXTNAME_TYPE_MAP[extname]
      if !file_type
        puts "Skipping file with unsupported extension: #{extname}"
        next
      end

      # Define the file-type-specific ImageMagick command prefix.
      cmd_prefix =
        case file_type
        when :image then "#{args.im_executable} #{filename}"
        when :pdf then "#{args.im_executable} -density #{args.density} #{filename}[0]"
        end

      # Get the lowercase filename without any leading path and extension.
      base_filename = File.basename(filename, extname).downcase

      # Generate the thumb image.
      thumb_filename=File.join([thumb_images_dir, "#{base_filename}_th.jpg"])
      if args.missing == 'false' or !File.exists?(thumb_filename)
        puts "Creating: #{thumb_filename}";
        system("#{cmd_prefix} -resize #{args.thumbs_size} -flatten #{thumb_filename}")
      end

      # Generate the small image.
      small_filename = File.join([small_images_dir, "#{base_filename}_sm.jpg"])
      if args.missing == 'false' or !File.exists?(small_filename)
        puts "Creating: #{small_filename}";
        system("#{cmd_prefix} -resize #{args.small_size} -flatten #{small_filename}")
      end
    end
  end


  ###############################################################################
  # normalize_object_filenames
  ###############################################################################

  desc "Rename the object files to match their corresponding objectid metadata value"
  task :normalize_object_filenames, [:force] do |t, args|
    args.with_defaults(
      :force => "false"
    )
    force = args.force == "true"

    config = load_config :DEVELOPMENT
    objects_dir = config[:objects_dir]
    objects_backup_dir = File.join([objects_dir, '_prenorm_backup'])

    FORMAT_EXTENSION_MAP = {
      'image/jpg' => '.jpg',
      'application/pdf' => '.pdf'
    }

    VALID_FORMATS = Set[*FORMAT_EXTENSION_MAP.keys]

    def get_normalized_filename(objectid, format)
      return "#{objectid}#{FORMAT_EXTENSION_MAP[format]}"
    end

    # Prompt whether user wants to continue if a non-empty backup
    # directory already exists.
    if Dir.exists?(objects_backup_dir) and !Dir.empty?(objects_backup_dir)
      res = prompt_user_for_confirmation "It looks like your object filenames " \
                                         "have already been normalized. Skip this step?"
      if res == true
        next
      end
    end

    # Do a dry run to check that:
    #  - there are no objectid collisions
    #  - there are no filename collisions
    #  - all format values are valid
    #  - all referenced filenames are present
    #  - the existing filename extension matches the format
    #  - no renamed filename will overwrite an existing
    seen_objectids = Set[]
    duplicate_objectids = Set[]
    seen_filenames = Set[]
    duplicate_filenames = Set[]
    invalid_formats = Set[]
    missing_files = Set[]
    invalid_extensions = Set[]
    existing_filename_collisions = Set[]
    num_items = 0
    config[:metadata].each do |item|
      # Check for objectids collisions.
      objectid = item['objectid']
      if seen_objectids.include? objectid
        duplicate_objectids.add objectid
      else
        seen_objectids.add objectid
      end

      # Check that the format is valid.
      format = item['format']
      if !VALID_FORMATS.include? format
        invalid_formats.add format
      end

      filename = item['filename']
      # Check for metadata filename collisions.
      if seen_filenames.include? filename
        duplicate_filenames.add filename
      else
        seen_filenames.add filename
      end
      # Check whether the file exists.
      if !File.exist? File.join([objects_dir, filename])
        missing_files.add filename
      end

      # Check that the existing filename extension matches the format.
      extension = File.extname(filename)
      if extension != FORMAT_EXTENSION_MAP[format]
        invalid_extensions.add extension
      end

      # If the new filename is different than the one specified in the metadata,
      # Check that the new filename will not overwrite an existing file.
      normalized_filename = get_normalized_filename(objectid, format)
      if normalized_filename != filename and File.exist? File.join([objects_dir, normalized_filename])
        existing_filename_collisions.add normalized_filename
      end

      num_items += 1
    end

    if (duplicate_objectids.size +
        duplicate_filenames.size +
        invalid_formats.size +
        missing_files.size +
        invalid_extensions.size +
        existing_filename_collisions.size
       ) > 0
      print "The following errors were detected:\n"
      if duplicate_objectids.size > 0
        print " - metadata contains duplicate 'objectid' value(s): #{duplicate_objectids.to_a}\n"
      end
      if duplicate_filenames.size > 0
        print " - metadata contains duplicate 'filename' value(s): #{duplicate_filenames.to_a}\n"
      end
      if invalid_formats.size > 0
        print " - metadata specifies unsupported 'format' value(s): #{invalid_formats.to_a}\n"
      end
      if missing_files.size > 0
        print " - metadata specifies 'filename' value(s) for which a file does not exist: #{missing_files.to_a}\n"
      end
      if invalid_extensions.size > 0
        print " - existing filename extensions do not match their format: #{invalid_extensions.to_a}\n"
      end
      if existing_filename_collisions.size > 0
        print " - renamed files would have overwritten existing files: #{existing_filename_collisions.to_a}\n"
      end
      if !force
        # Abort the task
        abort
      else
        print "The 'force' argument was specified, continuing...\n"
      end
    end

    # Everything looks good - do the renaming.
    res = prompt_user_for_confirmation "Rename #{num_items} files to match their objectid?"
    if res == false
      abort
    end

    # Optionally backup the original files.
    res = prompt_user_for_confirmation "Create backups of the original files in #{objects_backup_dir} ?"
    if res == true
      $ensure_dir_exists.call objects_backup_dir
      Dir.glob(File.join([objects_dir, '*'])).each do |filename|
        if !File.directory? filename
          FileUtils.cp(
            filename,
            File.join([objects_backup_dir, File.basename(filename)])
          )
        end
      end
    end

    config[:metadata].each do |item|
      objectid = item['objectid']
      filename = item['filename']
      format = item['format']

      normalized_filename = get_normalized_filename(objectid, format)

      # Leave the file alone if its filename is already normalized.
      if normalized_filename == filename
        next
      end

      existing_path = File.join([objects_dir, filename])
      new_path = File.join([objects_dir, normalized_filename])
      File.rename(existing_path, new_path)

      print "Renamed \"#{existing_path}\" to \"#{new_path}\"\n"
    end

    # Check whether any files with a filename derived from the old filenames exist.
    extracted_text_files = Dir.glob("#{config[:extracted_pdf_text_dir]}/*")
    derivative_files = (Dir.glob("#{config[:thumb_images_dir]}/*") +
                        Dir.glob("#{config[:small_images_dir]}/*"))

    if extracted_text_files.size > 0
      print "\nIt looks like you ran the extract_pdf_text task before normalizing the filenames. Since the extracted text files are given names that are based on that of the original file, you need to delete the existing files and run the extract_pdf_text task again.\n"
      res = prompt_user_for_confirmation "Delete the existing extracted PDF text files now?"
      if res == true
        FileUtils.rm extracted_text_files
      end
      print "Deleted #{extracted_text_files.size} extracted text files from \"#{config[:extracted_pdf_text_dir]}\". Remember to rerun the extract_pdf_text rake task.\n"
    end

    if derivative_files.size > 0
      print "\nIt looks like you ran the generate_derivatives task before normalizing the filenames. Since the direvative files are given names that are based on that of the original file, you need to delete the existing files and run the generate_derivatives task again.\n"
      res = prompt_user_for_confirmation "Delete the existing derivative files now?"
      if res == true
        FileUtils.rm derivative_files
        print "Deleted #{derivative_files.size} derivative files from \"#{config[:thumb_images_dir]}\" and/or \"#{config[:small_images_dir]}\". Remember to rerun the generate_derivatives rake task.\n"
      end
    end

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


  ###############################################################################
  # sync_objects
  #
  # Upload objects from your local objects/ dir to a Digital Ocean Space or other
  # S3-compatible storage.
  # For information on how to configure your credentials, see:
  # https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/setup-config.html#aws-ruby-sdk-credentials-shared
  #
  ###############################################################################

  task :sync_objects, [ :aws_profile ] do |t, args |
    args.with_defaults(
      :aws_profile => "PRODUCTION"
    )

    # Get the local objects directories from the development configuration.
    dev_config = load_config :DEVELOPMENT
    objects_dir = dev_config[:objects_dir]
    thumb_images_dir = dev_config[:thumb_images_dir]
    small_images_dir = dev_config[:small_images_dir]

    # Parse the S3 components from the remove_objects_url.
    s3_url = load_config(:PRODUCTION_PREVIEW)[:remote_objects_url]
    bucket, region, prefix, endpoint = parse_digitalocean_space_url s3_url

    # Create the S3 client.
    credentials = Aws::SharedCredentials.new(profile_name: args.aws_profile)
    s3_client = Aws::S3::Client.new(
      endpoint: endpoint,
      region: region,
      credentials: credentials
    )

    # Iterate over the object files and put each into the remote bucket.
    num_objects = 0
    [ objects_dir, thumb_images_dir, small_images_dir ].each do |dir|
      # Enforce a requirement by the subsequent object key generation code that each
      # enumerated directory path starts with objects_dir.
      if !dir.start_with? objects_dir
        raise "Expected dir to start with \"#{objects_dir}\", got: \"#{dir}\""
      end

      Dir.glob(File.join([dir, '*'])).each do |filename|
        # Ignore subdirectories.
        if File.directory? filename
          next
        end

        # Generate the remote object key using any specified digital-objects prefix and the
        # location of the local file relative to the objects dir.
        key = "#{prefix}/#{dir[objects_dir.length..]}/#{File.basename(filename)}"
                .gsub('//', '/')
                .delete_prefix('/')

        puts "Uploading \"#{filename}\" as \"#{key}\"..."
        s3_client.put_object(
          bucket: bucket,
          key: key,
          body: File.open(filename, 'rb'),
          acl: 'public-read'
        )

        num_objects += 1
      end
    end

    puts "Uploaded #{num_objects} objects"

  end

# Close the namespace.
end
