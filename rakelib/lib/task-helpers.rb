
require_relative './constants'

# If a specified directory doesn't exist, create it.
$ensure_dir_exists = ->(dir) { if !Dir.exists?(dir) then Dir.mkdir(dir) end }


# Abort if the env value specified to a rake task is invalid.
def assert_env_arg_is_valid env, valid_envs=["DEVELOPMENT", "PRODUCTION_PREVIEW", "PRODUCTION"]
  if !valid_envs.include? env
    abort "Invalid environment value: \"#{env}\". Please specify one of: #{valid_envs}"
  end
end


# Abort if the env value specified to a rake task is invalid.
def assert_required_args args, req_args
  # Assert that the task args object includes a non-nil value for each arg in req_args.
  missing_args = req_args.filter { |x| !args.has_key?(x) or args.fetch(x) == nil }
  if missing_args.length > 0
    abort "The following required task arguments must be specified: #{missing_args}"
  end
end


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


# Format a string for inclusion in a filename.
def filename_escape url
  return url.downcase.gsub(/[^a-z0-9\-_]/, '_')
end


# Format and print a message as an announcement.
def announce msg
  puts "\n**** #{msg}"
end

# Convert a collection URL to an Elasticseatch index name using filename_escape
# but with <scheme>:// and any trailing / removed.
def collection_url_to_elasticsearch_index collection_url
  return filename_escape(collection_url.split('://', 2)[1].delete_suffix('/'))
end

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
