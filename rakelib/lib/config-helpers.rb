
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

  # Load specific configuration files.
  collections_config = CSV.parse(File.read($COLLECTIONS_CONFIG_PATH), headers: true)

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
