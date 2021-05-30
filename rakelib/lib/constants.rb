
# This file defines all of the constants and default configuration values used
# by the various rake tasks.

require "cgi"


###############################################################################
# Configuration - customize these values to suit your application
###############################################################################

$ENV_CONFIG_FILENAMES_MAP = {
  :DEVELOPMENT => [ '_config.yml' ],
  :PRODUCTION_PREVIEW => [ '_config.yml', '_config.production_preview.yml' ],
  :PRODUCTION => [ '_config.yml', '_config.production.yml' ],
}

$ES_BULK_DATA_FILENAME = 'es_bulk_data.jsonl'

$ES_CREDENTIALS_PATH = File.join [Dir.home, ".elasticsearch", "credentials"]

# https://www.elastic.co/guide/en/elasticsearch/reference/current/cron-expressions.html
$ES_CRON_DAILY_AT_MIDNIGHT = '0 0 0 * * ?'
$ES_DEFAULT_SCHEDULED_SNAPSHOT_SCHEDULE = $ES_CRON_DAILY_AT_MIDNIGHT

$ES_DEFAULT_SNAPSHOT_POLICY_NAME = 'default'

$ES_DEFAULT_SNAPSHOT_REPOSITORY_BASE_PATH = '_elasticsearch_snapshots'

$ES_DEFAULT_SNAPSHOT_REPOSITORY_NAME = 'default'

$ES_DIRECTORY_INDEX_SETTINGS = {
  :mappings => {
    :properties => {
      :index => {
        :type => "text",
        :index => false,
      },
      :title => {
        :type => "text",
        :index => false,
      },
      :description => {
        :type => "text",
        :index => false,
      },
      :doc_count => {
        :type => "integer",
        :index => false,
      }
    }
  }
}

$ES_INDEX_SETTINGS_FILENAME = 'es_index_settings.json'

# Define an Elasticsearch snapshot name template that will automatically include the current date and time.
# See: https://www.elastic.co/guide/en/elasticsearch/reference/current/date-math-index-names.html#date-math-index-names
$ES_MANUAL_SNAPSHOT_NAME_TEMPLATE = CGI.escape "<manual-snapshot-{now/d{yyyyMMdd-HHmmss}}>"

$ES_SCHEDULED_SNAPSHOT_NAME_TEMPLATE = "<scheduled-snapshot-{now/d{yyyyMMdd-HHmm}}>"

$S3_URL_REGEX = /^https?:\/\/(?<bucket>[^\.]+)\.(?<region>\w+)(?:\.cdn)?\.digitaloceanspaces\.com(?:\/(?<prefix>.+))?$/

$SEARCH_CONFIG_PATH = File.join(['_data', 'config-search.csv'])

# Define a mapping from environment symbols to Elasticsearch profile names.
$ENV_ES_PROFILE_MAP = {
  :DEVELOPMENT => nil,
  :PRODUCTION_PREVIEW => 'PRODUCTION',
  :PRODUCTION => 'PRODUCTION',
}

# Define a mapping from Elasticsearch profile names to environment symbols.
$ES_PROFILE_ENV_MAP = {
  nil => :DEVELOPMENT,
  'PRODUCTION' =>  :PRODUCTION,
}

# Define a mapping from environment symbols to AWS profile names.
$ENV_AWS_PROFILE_MAP = {
  :PRODUCTION_PREVIEW => 'default',
  :PRODUCTION => 'default',
}


###############################################################################
# Constants - these values should not be modified
###############################################################################

$APPLICATION_JSON = 'application/json'
