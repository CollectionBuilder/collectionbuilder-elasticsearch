
require_relative 'lib/config-helpers'
require_relative 'lib/constants'
require_relative 'lib/task-helpers'
require_relative 'lib/elasticsearch-helpers'

require 'json'


# Define an Elasticsearch error response abort helper.
def _abort what_failed, data
  abort "[ERROR] #{what_failed} failed - " \
        "Elasticsearch responded with:\n#{JSON.pretty_generate(data)}"
end


# Define a create_index helper for use by both the create_index and
# create_directory_index tasks that returns a bool indicating whether the
# index was created.
def _create_index profile, index, settings
  # Attempt to create the index.
  res = create_index profile, index, settings, raise_for_status: false

  if res.code == '200'
    # The HTTP response code is 200, indicating that the index was created.
    # Print a message to the console and return true.
    puts "Created Elasticsearch index: #{index}"
    return true
  end

  # The HTTP response code was not 200.
  # Decode the JSON response body to read the error.
  data = JSON.load res.body

  # If creation failed because the index already exists, print a message
  # to the console and return false.
  if data['error']['type'] == 'resource_already_exists_exception'
    puts "Elasticsearch index (#{index}) already exists"
    return false
  end

  # Abort on unexpected error.
  _abort 'Index creation', data
end


# Define a _delete_index helper for use by both the delete_index and
# delete_directory_index tasks that returns a bool indicating whether the
# index was deleted.
def _delete_index profile, index
  # Confirm that the user really wants to delete the index.
  res = prompt_user_for_confirmation "Really delete index \"#{index}\"?"
  if res == false
    return false
  end

  # Attempt to delete the index.
  res = delete_index profile, index, raise_for_status: false

  if res.code == '200'
    # The HTTP response code is 200, indicating that the index was created.
    # Print a message to the console and return true.
    puts "Deleted Elasticsearch index: #{index}"
    return true
  end

  # Decode the JSON response body to read the error.
  data = JSON.load res.body

  # If creation failed because the index didn't exist, print a message
  # to the console and return false.
  if data['error']['type'] == 'index_not_found_exception'
    puts "Delete failed. Elasticsearch index (#{index}) does not exist."
    return false
  end

  # Abort on unexpected error.
  _abort 'Index deletion', data
end


# Enclose Elasticsearch-related tasks in a namespaced called "es", to be
# executed using the convention: `rake es:{task_name}`
namespace :es do


  ###############################################################################
  # list_indices
  ###############################################################################

  desc "Pretty-print the list of existing indices to the console"
  task :list_indices, [:profile] do |t, args|
    # Make the API request, letting it fail if the response status != 200.
    res = cat_indices args.profile

    # Decode the response data.
    data = JSON.load res.body

    # Prett-print the response data.
    puts JSON.pretty_generate(data)
  end


  ###############################################################################
  # create_index
  ###############################################################################

  desc "Create the Elasticsearch index"
  task :create_index, [:profile] do |t, args|
    # Read the index name from the config.
    config = $get_config_for_es_profile.call args.profile
    index = config[:elasticsearch_index]

    # Load the index settings from the local generated index settings file.
    dev_config = load_config :DEVELOPMENT
    settings_file_path = File.join([dev_config[:elasticsearch_dir], $ES_INDEX_SETTINGS_FILENAME])

    # Read the settings file.
    settings = JSON.load File.open(settings_file_path, 'r', encoding: 'utf-8')

    # Call the _create_index helper.
    _create_index args.profile, index, settings

    # Update the directory index if it exists.
    Rake::Task['es:update_directory_index'].invoke args.profile, 'false'
  end


  ###############################################################################
  # delete_index
  ###############################################################################

  desc "Delete the Elasticsearch index"
  task :delete_index, [:profile] do |t, args|
    # Read the index name from the config.
    config = $get_config_for_es_profile.call args.profile
    index = config[:elasticsearch_index]

    # Call the _delete_index helper.
    _delete_index args.profile, index

    # Update the directory index if it exists.
    Rake::Task['es:update_directory_index'].invoke args.profile, 'false'
  end


  ###############################################################################
  # create_directory_index
  ###############################################################################

  desc "Create the Elasticsearch directory index"
  task :create_directory_index, [:profile] do |t, args|
    # Read the directory index name from the config.
    config = $get_config_for_es_profile.call args.profile
    index = config[:elasticsearch_directory_index]

    # Read the directory index settings from a global constant.
    settings = $ES_DIRECTORY_INDEX_SETTINGS

    # Call the _create_index helper.
    _create_index args.profile, index, settings
  end


  ###############################################################################
  # update_directory_index
  ###############################################################################

  desc "Update the Elasticsearch directory index to reflect the current indices"
  task :update_directory_index, [:profile, :raise_on_missing] do |t, args|
    args.with_defaults(
      :raise_on_missing => 'true'
    )
    profile = args.profile
    raise_on_missing = args.raise_on_missing == 'true'

    config = $get_config_for_es_profile.call profile
    directory_index = config[:elasticsearch_directory_index]

    # Get the list of existing indices.
    res = cat_indices args.profile
    all_indices = JSON.load res.body

    # If no directory index exists, either raise an exception or silently return based on
    # the value of raise_on_missing.
    if !all_indices.any? { |x| x['index'] == directory_index }
      if raise_on_missing
        raise "Directory index (#{directory_index}) does not exist"
      else
        next
      end
    end

    # Get the list of collection indices by filtering out the directory and internal indices.
    collection_indices = all_indices.reject {
      |x| x['index'].start_with? '.' or x['index'] == directory_index
    }

    # Create a <collection-name> => <index_data> map.
    collection_name_index_map = Hash[ collection_indices.map { |x| [ x['index'], x ] } ]

    # Get the existing directory index documents.
    res = make_request profile, :GET, "/#{directory_index}/_search"
    data = JSON.load res.body

    directory_indices = data['hits']['hits'].map { |x| x['_source'] }
    directory_name_index_map = Hash[ directory_indices.map { |x| [ x['index'], x ] } ]

    # Delete any old collection indices from the directory.
    indices_to_remove = directory_name_index_map.keys - collection_name_index_map.keys
    indices_to_remove.each do |index_name|
      delete_document profile, directory_index, index_name
      puts "Deleted (#{index_name}) from the directory index"
    end

    # Add any new collection indices to the directory.
    indices_to_add = collection_name_index_map.keys - directory_name_index_map.keys
    indices_to_add.each do |index_name|
      index = collection_name_index_map[index_name]
      index_name = index['index']

      # Get the title and description values from the index mapping.
      index_meta = get_index_metadata profile, index_name

      document = {
        :index => index_name,
        :doc_count => index['docs.count'],
        :title => index_meta['title'],
        :description => index_meta['description']
      }

      res = update_document profile, directory_index, index_name, document
      puts "Added (#{index_name}) to the directory index"
    end
  end


  ###############################################################################
  # delete_directory_index
  ###############################################################################

  desc "Delete the Elasticsearch directory index"
  task :delete_directory_index, [:profile] do |t, args|
    # Read the directory index name from the config.
    config = $get_config_for_es_profile.call args.profile
    index = config[:elasticsearch_directory_index]

    # Call the _delete_index helper.
    _delete_index args.profile, index
  end


  ###############################################################################
  # create_snapshot_s3_repository
  ###############################################################################

  desc "Create an Elasticsearch snapshot repository that uses S3-compatible storage"
  task :create_snapshot_s3_repository,
       [:profile, :bucket, :base_path, :repository_name] do |t, args|

    args.with_defaults(
      :base_path => $ES_DEFAULT_SNAPSHOT_REPOSITORY_BASE_PATH,
      :repository_name => $ES_DEFAULT_SNAPSHOT_REPOSITORY_NAME,
    )

    bucket = args.bucket
    # If bucket was not specified, attempt to parse a default value from the config
    # remote_objects_url.
    if bucket == nil
      config = $get_config_for_es_profile.call args.profile
      if config.has_key? :remote_objects_url
        begin
          bucket, = parse_digitalocean_space_url config[:remote_objects_url]
        rescue
        end
      end
    end

    if bucket == nil
      # Bucket was not specified and we could not parse a default value from the
      # config remote_objects_url.
      assert_required_args args, [ :bucket ]
    end

    # Make the API request.
    res = create_snapshot_repository args.profile, args.repository_name, 's3',
                                     { :bucket => bucket, :base_path => args.base_path },
                                     raise_for_status: false

    # Abort on unexpected error.
    if res.code != '200'
      data = JSON.load res.body
      _abort 'Snapshot repository creation', data
    end

    puts "Elasticsearch S3 snapshot repository (#{args.repository_name}) created"
  end


  ###############################################################################
  # list_snapshot_repositories
  ###############################################################################

  desc "List the existing Elasticsearch snapshot repositories"
  task :list_snapshot_repositories, [:profile] do |t, args|
    # Make the API request.
    res = get_snapshot_repositories args.profile, raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    # Abort on unexpected error.
    if res.code != '200'
      _abort 'Get snapshot repositories', data
    end

    # Print the response data.
    puts JSON.pretty_generate(data)
  end


  ###############################################################################
  # list_snapshots
  ###############################################################################

  desc "List available Elasticsearch snapshots"
  task :list_snapshots, [:profile, :repository_name] do |t, args|
    args.with_defaults(
      :repository_name => $ES_DEFAULT_SNAPSHOT_REPOSITORY_NAME,
    )

    # Make the API request.
    res = get_repository_snapshots args.profile, args.repository_name,
                                   raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    # Abort un unexpected error.
    if res.code != '200'
      _abort 'List snapshots', data
    end

    # Pretty-print the response data.
    puts JSON.pretty_generate(data)
  end


  ###############################################################################
  # create_snapshot
  ###############################################################################

  desc "Create a new Elasticsearch snapshot"
  task :create_snapshot, [:profile, :repository, :wait] do |t, args|
    args.with_defaults(
      :repository => $ES_DEFAULT_SNAPSHOT_REPOSITORY_NAME,
      :wait => 'true'
    )

    # Make the request.
    res = create_snapshot args.profile, args.repository, wait: args.wait == 'true',
                          raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    if res.code != '200'
      _abort 'Create snapshot', data
    end

    puts "Snapshot created"
  end


  ###############################################################################
  # restore_snapshot
  ###############################################################################

  desc "Restore an Elasticsearch snapshot"
  task :restore_snapshot, [:profile, :snapshot_name, :wait, :repository_name] do |t, args|
    assert_required_args(args, [ :snapshot_name ])
    args.with_defaults(
      :repository_name => $ES_DEFAULT_SNAPSHOT_REPOSITORY_NAME,
      :wait => 'true'
    )
    wait = args.wait == 'true'

    # Make the API request.
    res = restore_snapshot args.profile, args.repository_name, args.snapshot_name, wait: wait,
                           raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    if res.code != '200'
      _abort 'Restore snapshot', data
    elsif wait
      puts "Snapshot (/#{args.repository_name}/#{args.snapshot_name}) restored"
    else
      # Pretty-print the JSON response.
      puts JSON.pretty_generate(data)
    end
  end


  ###############################################################################
  # delete_snapshot
  ###############################################################################

  desc "Delete an Elasticsearch snapshot"
  task :delete_snapshot, [:profile, :snapshot, :repository] do |t, args|
    assert_required_args(args, [:snapshot])
    args.with_defaults(
      :repository => $ES_DEFAULT_SNAPSHOT_REPOSITORY_NAME,
    )
    snapshot = args.snapshot

    # Make the request.
    res = delete_snapshot args.profile, args.repository, snapshot,
                          raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    if res.code == '200'
      puts "Deleted Elasticsearch snapshot: \"#{snapshot}\""
    else
      if data['error']['type'] == 'snapshot_missing_exception'
        puts "No Elasticsearch snapshot found for name: \"#{snapshot}\""
      else
        _abort 'Delete snapshot', data
      end
    end
  end


  ###############################################################################
  # load_bulk_data
  ###############################################################################

  desc "Load index data using the Bulk API"
  task :load_bulk_data, [:profile, :datafile_path] do |t, args|
    # The data file must be a newline-separated JSON file as described here: https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html#docs-bulk-api-desc
    datafile_path = args.datafile_path
    if datafile_path == nil
      dev_config = load_config :DEVELOPMENT
      datafile_path = File.join([dev_config[:elasticsearch_dir], $ES_BULK_DATA_FILENAME])
    end
    data = File.open(datafile_path, 'rb').read

    res = load_bulk_data args.profile, data, raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    if res.code != '200'
      _abort 'Restore snapshot', data
    end

    # Collect item counts.
    index_num_items_map = {}
    num_other_ops = 0
    data['items'].each do |item|
      # The Bulk API supports several types of operations but we only expect 'index' operations
      # here, so if not an 'index', count and ignore.
      if !item.has_key? 'index'
        num_other_ops += 1
        next
      end
      index = item['index']['_index']
      if !index_num_items_map.has_key? index
        index_num_items_map[index] = 1
      else
        index_num_items_map[index] += 1
      end
    end

    if index_num_items_map.length > 0
      puts 'Indexed the following number of indice items:'
      index_num_items_map.entries.map do |index, count|
        puts "  #{index}: #{count}"
      end
    end

    if num_other_ops > 0
      puts "Datafile (#{datafile_path}) also included #{num_other_ops} non-index operations"
    end
  end


  ###############################################################################
  # delete_snapshot_repository
  ###############################################################################

  desc "Delete an Elasticsearch snapshot repository"
  task :delete_snapshot_repository, [:profile, :repository] do |t, args|
    assert_required_args(args, [:repository])
    repository = args.repository

    # Make the request.
    res = delete_snapshot_repository args.profile, repository, raise_for_status: false

    if res.code == '200'
      puts "Deleted Elasticsearch snapshot repository: \"#{repository}\""
    else
      data = JSON.load res.body
      if data['error']['type'] == 'repository_missing_exception'
        puts "No Elasticsearch snapshot repository found for name: \"#{repository}\""
      else
        _abort 'Delete snapshot repository', data
      end
    end
  end


  ###############################################################################
  # create_snapshot_policy
  ###############################################################################

  desc "Create a policy to enable automatic Elasticsearch snapshots"
  task :create_snapshot_policy, [:profile, :policy, :repository, :schedule] do |t, args|
    args.with_defaults(
      :policy => $ES_DEFAULT_SNAPSHOT_POLICY_NAME,
      :repository => $ES_DEFAULT_SNAPSHOT_REPOSITORY_NAME,
      :schedule => $ES_DEFAULT_SCHEDULED_SNAPSHOT_SCHEDULE,
    )

    # Define a snapshot policy that excludes .security* indices,
    # and retains a min/max of 5/50 snapshots for 30 days.
    data = {
      :schedule => args.schedule,
      :name => $ES_SCHEDULED_SNAPSHOT_NAME_TEMPLATE,
      :repository => args.repository,
      :config => { :indices => [ '*', '-.security*' ] },
      :rentention => {
        :expire_after => '30d',
        :min_count => 5,
        :max_count => 50
      }
    }

    res = create_snapshot_policy args.profile, args.policy, data,
                                 raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    if res.code != '200'
      _abort 'Create snapshot policy', data
    end
    puts "Elasticsearch snapshot policy (#{args.policy}) created"
  end


  ###############################################################################
  # execute_snapshot_policy
  ###############################################################################

  desc "Manually execute an existing Elasticsearch snapshot policy"
  task :execute_snapshot_policy, [:profile, :policy] do |t, args|
    args.with_defaults(
      :policy => $ES_DEFAULT_SNAPSHOT_POLICY_NAME,
    )

    res = execute_snapshot_policy args.profile, args.policy, raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    if res.code != '200'
      _abort 'Execute snapshot policy', data
    end
    puts "Elasticsearch snapshot policy (#{args.policy}) was executed.\n" +
         "Run \"rake es:list_snapshot_policies[#{args.profile}]\" to check its status."
  end


  ###############################################################################
  # list_snapshot_policies
  ###############################################################################

  desc "List the currently-defined Elasticsearch snapshot policies"
  task :list_snapshot_policies, [:profile] do |t, args|
    res = get_snapshot_policy args.profile

    # Decode the response data.
    data = JSON.load res.body

    if res.code != '200'
      _abort 'List snapshot policies', data
    end

    # Pretty-print the response.
    puts JSON.pretty_generate(data)
  end


  ###############################################################################
  # delete_snapshot_policy
  ###############################################################################

  desc "Delete an Elasticsearch snapshot policy"
  task :delete_snapshot_policy, [:profile, :policy] do |t, args|
    args.with_defaults(
      :policy => $ES_DEFAULT_SNAPSHOT_POLICY_NAME,
    )
    policy = args.policy

    res = delete_snapshot_policy args.profile, policy, raise_for_status: false

    # Decode the response data.
    data = JSON.load res.body

    if res.code == '200'
      puts "Deleted Elasticsearch snapshot policy: \"#{policy}\""
    else
      if data['error']['type'] == 'resource_not_found_exception'
        puts "No Elasticsearch snapshot policy found for name: \"#{policy}\""
      else
        _abort 'Delete snapshot policy', data
      end
    end
  end


  ###############################################################################
  # ready
  ###############################################################################
  desc "Display whether the Elasticsearch instance is up and running"
  task :ready, [:profile] do |t, args|
    puts "ready: #{elasticsearch_ready(args.profile)}"
  end


# Close the namespace.
end
