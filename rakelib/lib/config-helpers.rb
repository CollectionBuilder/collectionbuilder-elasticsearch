
require 'csv'
require 'yaml'

require_relative 'constants'


def get_validate_collections_config
  # Read and parse the file.
  collections_config = CSV.parse(File.read($COLLECTIONS_CONFIG_PATH), headers: true)

  # Abort if no collections are configured.
  if collections_config.length == 0
    abort "Please configure at least one collection in #{$COLLECTIONS_CONFIG_PATH}"
  end

  # Abort if any unsupported fields are defined.
  invalid_keys = collections_config.first.headers.to_set.difference(
    $VALID_COLLECTION_CONFIG_KEYS
  )
  if invalid_keys.length > 0
    abort "#{$COLLECTIONS_CONFIG_PATH} contains unsupported fields: #{[*invalid_keys]}"
  end

  # Abort if any required fields are missing.
  missing_required_field_counts = Hash.new(0)
  collections_config.each do |config|
    $REQUIRED_COLLECTION_CONFIG_KEYS.each do |k|
      if not config[k]
        missing_required_field_counts["num_missing_#{k}"] += 1
      end
    end
  end
  if missing_required_field_counts.length > 0
    abort "#{$COLLECTIONS_CONFIG_PATH} is missing required values: " \
          "#{missing_required_field_counts}"
  end

  return collections_config
end


def load_config env = :DEVELOPMENT
  # Read the config files and validate and return the values required by rake
  # tasks.

  # Get the config as defined by the env argument.
  filenames = $ENV_CONFIG_FILENAMES_MAP[env]
  config = {}
  filenames.each do |filename|
    config.update(YAML.load_file filename)
  end

  # Load specific configuration files.
  collections_config = get_validate_collections_config

  return {
    :collections_config => collections_config,
    :elasticsearch_protocol => config['elasticsearch-protocol'],
    :elasticsearch_host => config['elasticsearch-host'],
    :elasticsearch_port => config['elasticsearch-port'],
    :elasticsearch_index => config['elasticsearch-index'],
    :elasticsearch_directory_index => config['elasticsearch-directory-index'],
  }
end


$get_config_for_es_profile =->(profile) { load_config $ES_PROFILE_ENV_MAP[profile] }
