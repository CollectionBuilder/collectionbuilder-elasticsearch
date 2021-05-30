
require 'csv'
require 'yaml'

require_relative 'constants'


def load_config env = :DEVELOPMENT
  # Read the config files and validate and return the values required by rake
  # tasks.

  # Get the config as defined by the env argument.
  filenames = $ENV_CONFIG_FILENAMES_MAP[env]
  config = {}
  filenames.each do |filename|
    config.update(YAML.load_file filename)
  end

  # Read the digital objects location.
  digital_objects_location = config['digital-objects']
  if !digital_objects_location
    raise "digital-objects is not defined in _config*.yml for environment: #{env}"
  end
  # Strip any trailing slash.
  digital_objects_location.delete_suffix! '/'

  # Load the collection metadata.
  metadata_name = config['metadata']
  if !metadata_name
    raise "metadata must be defined in _config.yml"
  end
  metadata_filename = File.join(['_data', "#{metadata_name}.csv"])
  # TODO - document the assumption that the metadata CSV is UTF-8 encoded.
  metadata_text = File.read(metadata_filename, :encoding => 'utf-8')
  metadata = CSV.parse(metadata_text, headers: true)

  # Load the search configuration.
  search_config = CSV.parse(File.read($SEARCH_CONFIG_PATH), headers: true)

  # Generate the collection URL by concatenating 'url' with 'baseurl'.
  stripped_url = (config['url'] || '').delete_suffix '/'
  stripped_baseurl = (config['baseurl'] || '').delete_prefix('/').delete_suffix('/')
  collection_url = "#{stripped_url}/#{stripped_baseurl}".delete_suffix '/'

  retval = {
    :metadata => metadata,
    :search_config => search_config,
    :collection_title => config['title'],
    :collection_description => config['description'],
    :collection_url => collection_url,
    :elasticsearch_protocol => config['elasticsearch-protocol'],
    :elasticsearch_host => config['elasticsearch-host'],
    :elasticsearch_port => config['elasticsearch-port'],
    :elasticsearch_index => config['elasticsearch-index'],
    :elasticsearch_directory_index => config['elasticsearch-directory-index'],
  }

  # Add environment-dependent values.
  if env == :DEVELOPMENT
    # If present, strip out the baseurl prefix.
    if config['baseurl'] and digital_objects_location.start_with? config['baseurl']
      digital_objects_location = digital_objects_location[config['baseurl'].length..-1]
      # Trim any leading slash from the objects directory
      digital_objects_location.delete_prefix! '/'
    end
    retval.update({
      :objects_dir => digital_objects_location,
      :thumb_images_dir => File.join([digital_objects_location, 'thumbs']),
      :small_images_dir => File.join([digital_objects_location, 'small']),
      :extracted_pdf_text_dir => File.join([digital_objects_location, 'extracted_text']),
      :elasticsearch_dir => File.join([digital_objects_location, 'elasticsearch']),
    })
  else
    # Environment is PRODUCTION_PREVIEW or PRODUCTION.
    retval.update({
      :remote_objects_url => digital_objects_location,
      :remote_thumb_images_url => "#{digital_objects_location}/thumbs",
      :remote_small_images_url => "#{digital_objects_location}/small",
    })
  end

  return retval
end


$get_config_for_es_profile =->(profile) { load_config $ES_PROFILE_ENV_MAP[profile] }


# Parse a Digital Ocean Space URL into its constituent S3 components, with the expectation
# that it has the format:
# <protocol>://<bucket-name>.<region>.cdn.digitaloceanspaces.com[/<prefix>]
# where the endpoint will be: <region>.digitaloceanspaces.com
def parse_digitalocean_space_url url
  match = $S3_URL_REGEX.match url
  if !match
    raise "digital-objects URL \"#{url}\" does not match the expected "\
          "pattern: \"#{$S3_URL_REGEX}\""
  end
  bucket = match[:bucket]
  region = match[:region]
  prefix = match[:prefix]
  endpoint = "https://#{region}.digitaloceanspaces.com"
  return bucket, region, prefix, endpoint
end
