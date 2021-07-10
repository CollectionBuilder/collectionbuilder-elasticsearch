
# This file defines tasks that execute sequences of individual task operations.

require_relative 'lib/task-helpers'

# Enclose CollectionBuilder-related tasks in a namespaced called "cb", to be
# executed using the convention: `rake cb:{task_name}`
namespace :cb do

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
    Rake::Task['cb:read_collections_metadata'].invoke

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
    Rake::Task['es:create_directory_index'].invoke profile

    banner_announce 'Create the collection search index'
    Rake::Task['es:create_index'].invoke profile

    banner_announce 'Load the collection data file into the search index'
    Rake::Task['es:load_bulk_data'].invoke profile

    # TODO - maybe also enable daily snapshots

    banner_announce 'Search index is loaded and ready!'
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
