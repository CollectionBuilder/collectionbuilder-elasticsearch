
# This file defines all of the constants and default configuration values used
# by the various rake tasks.

require 'cgi'
require_relative 'validators'


###############################################################################
# Types and Validators
###############################################################################

$URL_STRING = 'url_string'

$TYPE_VALIDATOR_MAP = {
  $URL_STRING => $is_valid_url
}


###############################################################################
# Configuration - customize these values to suit your application
###############################################################################

$ENV_CONFIG_FILENAMES_MAP = {
  :DEVELOPMENT => [ '_config.yml' ],
  :PRODUCTION_PREVIEW => [ '_config.yml', '_config.production_preview.yml' ],
  :PRODUCTION => [ '_config.yml', '_config.production.yml' ],
}

$ES_BULK_DATA_FILENAME = 'bulk_data.jsonl'

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

$ES_INDEX_SETTINGS_FILENAME = 'index_settings.json'

# Define an Elasticsearch snapshot name template that will automatically include the current date and time.
# See: https://www.elastic.co/guide/en/elasticsearch/reference/current/date-math-index-names.html#date-math-index-names
$ES_MANUAL_SNAPSHOT_NAME_TEMPLATE = CGI.escape "<manual-snapshot-{now/d{yyyyMMdd-HHmmss}}>"

$ES_SCHEDULED_SNAPSHOT_NAME_TEMPLATE = "<scheduled-snapshot-{now/d{yyyyMMdd-HHmm}}>"

$SEARCH_CONFIG_PATH = File.join(['_data', 'config-search.csv'])
$COLLECTIONS_CONFIG_PATH = File.join(['_data', 'config-collections.csv'])
$COLLECTIONS_DATA_DIR = File.join(['_data', 'collections'])
$COLLECTION_METADATA_FILENAME = 'collection-metadata.json'
$COLLECTION_OBJECTS_METADATA_FILENAME = 'objects-metadata.json'
$COLLECTION_PDFS_SUBDIR = 'pdfs'
$COLLECTION_EXTRACTED_PDF_TEXT_SUBDIR = 'extracted_pdfs_text'
$COLLECTION_ELASTICSEARCH_SUBDIR = 'elasticsearch'
$SEARCH_CONFIG_EXCLUDED_FIELDS = Set[
  'date is approximate',
  'duration',
  'filename',
  'identifier',
  'image_small',
  'image_thumb',
  'latitude',
  'longitude',
  'object_download',
  'object_template',
  'object_thumb',
  'objectid',
  'reference_url',
  'rights_statement',
  'standardized_rights',
  'transcriber',
  'type',
]
$SEARCH_CONFIG_DEFAULT_DISPLAY_FIELDS = [ 'title', 'date' ]

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

# Define the valid config-collections fields.
$VALID_COLLECTION_CONFIG_KEYS = [
  'homepage_url',
  'shortname',
  'title',
  'description',
  'objects_metadata_url',
  'image_url',
]

# Define which collection config fields must be specified.
$REQUIRED_COLLECTION_CONFIG_KEYS = [ 'homepage_url' ]

# Define the JSON-LD => collection-metadata-field mapping to use when retrieving
# metadata from the collection's homepage_url.
$JSON_LD_COLLECTION_METADATA_KEY_MAP = {
  'headline' => 'title',
  'description' => 'description',
  'image' => 'image_url',
}

# The generated collection metadata file has the same fields as
# config-collections.
$COLLECTION_METADATA_KEYS = $VALID_COLLECTION_CONFIG_KEYS

# Define the fields that must be specified in the final collection metadata
# either in the collections config file or retrieved via JSON-LD, which can
# not be otherwise derived.
$REQUIRED_COLLECTION_METADATA_KEYS = [
  'homepage_url',
  'title',
  'description',
]

$GENERABLE_COLLECTION_METADATA_KEYS = [
  'shortname',
  'objects_metadata_url',
]

# Define the CollectionBuilder site path where the JSON metadata file lives.
$COLLECTIONBUILDER_JSON_METADATA_PATH = '/assets/data/metadata.json'

# Define a mapping of canonical object metadata keys that are used during the
# build process to a prioritized list of key aliases. When looking up an object's
# metadata value, if the canonical key is absent or the corresponding value empty,
# a lookup using the first key in the aliases list will then be attempted, if that
# is absent or its corresponding value empty, the next alias will be attempted, ...
#
# For example, a previous version of the canonical schema used 'object_download'
# as the download URL key, whereas the current schema uses 'object_location'.
# To maintain compatibility with collections deployed using the old schema, we
# specify 'object_download' as an alias for 'object_location':
$OBJECT_METADATA_KEY_ALIASES_MAP = {
  'format' => [],
  'objectid' => [],
  'object_location' => [ 'object_download' ],
  'image_thumb' => [ 'object_thumb' ],
  'reference_url' => [],
}

# Define which object metadata fields must be present.
$REQUIRED_OBJECT_METADATA_FIELDS = Set[ 'reference_url' ]

# Define a objects metadata field -> type map for all non-arbitrary string fields
# so that we can enforce validation on these field values.
$OBJECT_METADATA_FIELD_TYPE_MAP = {
  'object_location' => $URL_STRING,
  'image_thumb' => $URL_STRING,
  'reference_url' => $URL_STRING
}

# Elasticsearch index settings-related configuration.
$TEXT_FIELD_DEF_KEYS = [ 'field' ]
$BOOL_FIELD_DEF_KEYS = [ 'index', 'display', 'facet', 'multi-valued' ]
$VALID_FIELD_DEF_KEYS = $TEXT_FIELD_DEF_KEYS.dup.concat $BOOL_FIELD_DEF_KEYS
$INDEX_SETTINGS_TEMPLATE = {
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


###############################################################################
# Universal constants - these values should not be modified
###############################################################################

$WARN = 'warn'
$RAISE = 'raise'
$IGNORE = 'ignore'

$APPLICATION_JSON = 'application/json'
$APPLICATION_PDF = 'application/pdf'
