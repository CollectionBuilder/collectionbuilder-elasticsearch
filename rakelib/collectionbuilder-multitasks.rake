
# This file defines tasks that execute sequences of individual task operations.


# Define a helper to announce the next task step.
def _announce_step step
  puts "\n**** #{step}"
end


# Enclose CollectionBuilder-related tasks in a namespaced called "cb", to be
# executed using the convention: `rake cb:{task_name}`
namespace :cb do

  ###############################################################################
  # build
  ###############################################################################

  desc "Execute all build steps required to go from metadata file and directory of " \
       "collection objects to a fully configured application"
  task :build, [:env] do |t, args|
    args.with_defaults(
      :env => 'DEVELOPMENT'
    )
    assert_env_arg_is_valid args.env
    env = args.env.to_sym

    _announce_step "Normalize collection object names"
    Rake::Task['cb:normalize_object_filenames'].invoke

    _announce_step "Generate collection object derivatives"
    Rake::Task['cb:generate_derivatives'].invoke

    # create_search_index announces its own steps.
    Rake::Task['cb:create_search_index'].invoke $ENV_ES_PROFILE_MAP[env]

    if env == :PRODUCTION_PREVIEW or env == :PRODUCTION
      _announce_step "Sync objects to the Digital Ocean Space"
      Rake::Task['cb:sync_objects'].invoke $ENV_AWS_PROFILE_MAP[env]
    end
  end


  ###############################################################################
  # create_search_index
  ###############################################################################

  task :create_search_index, [:profile] do |t, args|
    profile = args.profile

    _announce_step 'Extract the text from PDF-type collection objects'
    Rake::Task['cb:extract_pdf_text'].invoke

    _announce_step 'Generate the collection search index data file'
    Rake::Task['cb:generate_search_index_data'].invoke profile

    _announce_step 'Generate the collection search index settings file'
    Rake::Task['cb:generate_search_index_settings'].invoke

    # Check that the Elasticsearch instance is available and accessible.
    while ! elasticsearch_ready profile
      puts 'Waiting for Elasticsearch... Is it running?'
      sleep 2
    end

    # Create the directory index before the collection index so that the call
    # to create_index will automatically update the directory.
    _announce_step 'Create the directory index'
    Rake::Task['es:create_directory_index'].invoke profile

    _announce_step 'Create the collection search index'
    Rake::Task['es:create_index'].invoke profile

    _announce_step 'Load the collection data file into the search index'
    Rake::Task['es:load_bulk_data'].invoke profile

    # TODO - maybe also enable daily snapshots

    _announce_step 'Search index is loaded and ready!'
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
