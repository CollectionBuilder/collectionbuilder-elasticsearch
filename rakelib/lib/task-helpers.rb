
require 'json'
require 'logger'
require 'open-uri'

require 'nokogiri'

require_relative './constants'
require_relative './exceptions'


###############################################################################
# Task Helpers
###############################################################################

# Abort if the env value specified to a rake task is invalid.
def assert_env_arg_is_valid env, valid_envs=['DEVELOPMENT', 'PRODUCTION_PREVIEW',
                                             'PRODUCTION']
  if !valid_envs.include? env
    abort "Invalid environment value: \"#{env}\". Please specify one of: #{valid_envs}"
  end
end


# Abort if not all required args have been specified to the rake take.
def assert_required_args args, req_args
  # Assert that the task args object includes a non-nil value for each arg in req_args.
  missing_args = req_args.filter { |x| !args.has_key?(x) or args.fetch(x) == nil }
  if missing_args.length > 0
    abort "The following required task arguments must be specified: #{missing_args}"
  end
end


###############################################################################
# User Interface Helpers
###############################################################################

# Prompt the user to confirm that they want to do what the message says
# and return a bool indicating their response.
def prompt_user_for_confirmation message
  response = nil
  while true do
    # Use print instead of puts to avoid trailing \n.
    print "#{message} (Y/n): "
    $stdout.flush
    response =
      case STDIN.gets.chomp.downcase
      when "", "y"
        true
      when "n"
        false
      else
        nil
      end
    if response != nil
      return response
    end
    puts "Please enter \"y\" or \"n\""
  end
end


# Print a message with emphasis.
def announce msg
  puts "\n**** #{msg}"
end


# Print a message inside a bordered box.
def banner_announce msg
  border = '*' * (msg.length + 10)
  puts "\n#{border}"
  puts "**** #{msg} ****"
  puts border
end


###############################################################################
# HTTP Helpers
###############################################################################

# Attempt to return the parsed JSON-LD data from a specified URL.
def fetch_json_ld url
  $logger.debug "Fetching JSON-LD from #{url}"
  begin
    res = URI.open url
  rescue
    $logger.warn "Could not open #{url}"
    return
  end

  begin
    doc = Nokogiri.parse res.read
  rescue
    $logger.warn "Response from #{url} is not valid HTML"
    return
  end

  elements = doc.css('script[type="application/ld+json"]')
  if elements.length == 0
    $logger.warn "Response from #{url} does not contain a JSON-LD script tag"
    return
  end

  if elements.length > 1
    $logger.warn "Reading only the first of multiple JSON-LD script tags at #{url}"
  end
  script_tag = elements[0]

  begin
    return JSON.parse(script_tag.text)
  rescue
    $logger.warn "JSON-LD script tag contents at #{url} is not valid JSON"
  end
end


###############################################################################
# String Transformation Helpers
###############################################################################

# Format a string for inclusion in a filename.
def filename_escape url
  return url.downcase.gsub(/[^a-z0-9\-_]/, '_')
end


# Convert a collection URL to an Elasticseatch index name using filename_escape
# but with <scheme>:// and any trailing / removed.
def collection_url_to_elasticsearch_index collection_url
  return filename_escape(collection_url.split('://', 2)[1].delete_suffix('/'))
end


###############################################################################
# Objects Metadata Validator / Getter
###############################################################################

# Define a helper to return an object metadata value based on a
# specified key and any defined, prioritized aliases.
def object_metadata_get metadata, k, missing_action=$WARN
  # Get any defined validator for this field.
  validator = $TYPE_VALIDATOR_MAP[$OBJECT_METADATA_FIELD_TYPE_MAP[k]]
  # Enumerate over k and its aliases and return the first non-nil/empty value
  # that satisfies any defined validator.
  [k, *($OBJECT_METADATA_KEY_ALIASES_MAP[k] or [])].each do |k|
    v = metadata[k]
    if !v.nil? and !v.empty? and (validator.nil? or validator.call(v))
      return v
    end
  end
  # No valid value was found.
  if missing_action == $IGNORE
    return nil
  end
  # Format the missing metadata value message. If the item includes an
  # objectid, create a short message using that, otherwise include the
  # whole item.
  objectid = metadata['objectid']
  if not objectid.nil? and not objectid.empty?
    msg = "objectid=#{metadata['objectid']} is missing a required "\
          "metadata value for (#{k})"
  else
    msg = "Object metadata is missing a required value for (#{k}): #{metadata}"
  end
  # Maybe take some missing-related action.
  case missing_action
  when $WARN
    $logger.warn msg
  when $RAISE
    raise InvalidObjectMetadataField.new msg
  else
    raise "Unsupported missing_action value: #{missing_action}"
  end
end


###############################################################################
# Filesystem Helpers
###############################################################################

# If a specified directory doesn't exist, create it.
$ensure_dir_exists = ->(dir) { if !Dir.exists?(dir) then Dir.mkdir(dir) end }


def get_ensure_collection_data_dir collection_url
  $ensure_dir_exists.call $COLLECTIONS_DATA_DIR
  escaped_collection_name = filename_escape collection_url
  collection_data_dir = File.join [$COLLECTIONS_DATA_DIR, "#{escaped_collection_name}"]
  $ensure_dir_exists.call collection_data_dir
  return collection_data_dir
end


def get_collection_metadata_path collection_url
  data_dir = get_ensure_collection_data_dir collection_url
  return File.join([ data_dir, $COLLECTION_METADATA_FILENAME ])
end


def read_collection_metadata collection_url
  metadata_path = get_collection_metadata_path collection_url
  begin
    return JSON.load File.open(metadata_path, 'rb')
  rescue Errno::ENOENT
    puts "ERROR: Collection metadata file (#{metadata_path}) not found for collection: "\
         "#{collection_url}"
    puts "Try running 'rake cb:read_collections_metadata' to automatically generate "\
         "this file."
    exit 1
  end
end


def get_collection_objects_metadata_path collection_url
  data_dir = get_ensure_collection_data_dir collection_url
  return File.join([ data_dir, $COLLECTION_OBJECTS_METADATA_FILENAME ])
end


def read_collection_objects_metadata collection_url
  objects_metadata_path = get_collection_objects_metadata_path collection_url
  begin
    return JSON.load(File.open(objects_metadata_path, 'rb'))['objects']
  rescue Errno::ENOENT
    puts "ERROR: Collection objects metadata file (#{objects_metadata_path}) not found "\
         "for collection: #{collection_url}"
    puts "Try running 'rake cb:download_collections_objects_metadata' to automatically "\
         "retrieve this file."
    exit 1
  end
end


def read_search_config
  # Return a search config <fieldName> => <configDict> map.
  field_config_map = {}
  begin
    field_defs = CSV.parse(File.read($SEARCH_CONFIG_PATH), headers: true)
  rescue Errno::ENOENT
    puts "ERROR: Search config file (#{objects_metadata_path}) not found."
    puts "Try running 'rake cb:generate_search_config' to generate it. "
    exit 1
  end
  field_defs.each do |row|
    field_config_map[row['field']] = row
  end
  return field_config_map
end


def get_ensure_collection_pdfs_dir collection_url
  collection_data_dir = get_ensure_collection_data_dir(collection_url)
  collection_pdfs_dir = File.join([collection_data_dir, $COLLECTION_PDFS_SUBDIR])
  $ensure_dir_exists.call collection_pdfs_dir
  return collection_pdfs_dir
end


def get_ensure_collection_extracted_pdf_text_dir collection_url
  collection_data_dir = get_ensure_collection_data_dir(collection_url)
  collection_extracted_pdf_text_dir = File.join(
    [collection_data_dir, $COLLECTION_EXTRACTED_PDF_TEXT_SUBDIR]
  )
  $ensure_dir_exists.call collection_extracted_pdf_text_dir
  return collection_extracted_pdf_text_dir
end


def get_ensure_collection_elasticsearch_dir collection_url
  collection_data_dir = get_ensure_collection_data_dir(collection_url)
  collection_elasticsearch_dir = File.join(
    [collection_data_dir, $COLLECTION_ELASTICSEARCH_SUBDIR]
  )
  $ensure_dir_exists.call collection_elasticsearch_dir
  return collection_elasticsearch_dir
end
