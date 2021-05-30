
require 'net/http'
require 'yaml'

require_relative 'config-helpers'
require_relative 'constants'


###############################################################################
# Elasticsearch Config Helpers
###############################################################################

# Return the credentials for the specified Elasticsearch profile.
def get_es_profile_credentials profile = "admin"
  creds = YAML.load_file $ES_CREDENTIALS_PATH
  if !creds.include? "profiles"
    raise "\"profiles\" key not found in: #{$ES_CREDENTIALS_PATH}"
  elsif !creds['profiles'].include? profile
    raise "No credentials found for profile: \"#{profile}\""
  else
    return creds['profiles'][profile]
  end
end


# Return the Elasticsearch protocol, host, port, and credentials for a given
# profile.
def get_es_profile_request_args profile
  config = $get_config_for_es_profile.call profile
  creds = if profile != nil then get_es_profile_credentials(profile) else nil end
  return config[:elasticsearch_protocol],
         config[:elasticsearch_host],
         config[:elasticsearch_port],
         creds
end


###############################################################################
# Elasticsearch HTTP Request Helpers
###############################################################################

def make_request profile, method, path, body: nil, headers: nil,
                 raise_for_status: true
  # Get the user-profile-specific request args.
  protocol, host, port, creds = get_es_profile_request_args profile

  # Set initheader to always accept/expect JSON responses.
  initheader = { 'Accept' => $APPLICATION_JSON }

  # Update initheader with any custom, specified headers.
  if headers != nil
    initheader.update(headers)
  end

  req_fn =
    case method
    when :GET
      Net::HTTP::Get
    when :PUT
      Net::HTTP::Put
    when :POST
      Net::HTTP::Post
    when :DELETE
      Net::HTTP::Delete    else
      raise "Unhandled HTTP method: #{method}"
    end

  req = req_fn.new(path, initheader=initheader)

  # If an Elasticsearch user was specified, use their credentials to configure
  # basic auth.
  if creds != nil
    req.basic_auth creds['username'], creds['password']
  end

  # Set any specified body.
  if body != nil
    req.body = body
  end

  # Make the request.
  begin
    res = Net::HTTP.start(host, port, :use_ssl => protocol == 'https') do |http|
    http.request(req)
    end
  rescue Errno::ECONNREFUSED
    puts "Elasticsearch not found at: #{host}:#{port}"
    if creds == nil
      puts 'By default, the Elasticsearch-related rake tasks attempt to operate on the local, ' +
           'development ES instance. If you want to operate on a production instance, please ' +
           'specify the <profile-name> rake task argument.'
    end
    exit 1
  end

  # Maybe raise an exception on non-HTTPSuccess (i.e. 2xx) response status.
  if raise_for_status and res.code.to_i >= 300
    raise "Elasticsearch Request Failed: #{res.body}"
  end

  return res
end


# Define a make_request() wrapper that takes care of setting the Content-Type
# and encoding the body of a JSON request.
def make_json_request profile, method, path, data, **kwargs
  return make_request(
    profile,
    method,
    path,
    body: JSON.dump(data),
    headers: { 'content-type' => $APPLICATION_JSON },
    **kwargs
  )
end


###############################################################################
# Misc Helpers
###############################################################################

# Get the index mapping _meta value.
def get_index_metadata profile, index
  res = make_request profile, :GET, "/#{index}/_mapping"
  data = JSON.load res.body
  return data[index]['mappings']['_meta']
end


# Return a boolean indicating whether the Elasticsearch instance is available.
def elasticsearch_ready profile
  begin
    res = make_request profile, :GET, "/"
  rescue StandardError
    return false
  else
    return res.code == '200'
  end
end


###############################################################################
# Elasticsearch API Endpoint Wrappers
###############################################################################

# https://www.elastic.co/guide/en/elasticsearch/reference/current/cat-indices.html
def cat_indices profile, **kwargs
  return make_request profile, :GET, '/_cat/indices', **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html
def create_index profile, index, settings, **kwargs
  return make_json_request profile, :PUT, "/#{index}", settings, **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-delete-index.html
def delete_index profile, index, **kwargs
  return make_request profile, :DELETE, "/#{index}", **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update.html
def update_document profile, index, doc_id, doc, **kwargs
  return make_json_request profile, :POST, "/#{index}/_doc/#{doc_id}", doc, **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete.html
def delete_document profile, index, doc_id, **kwargs
  return make_request profile, :DELETE, "/#{index}/_doc/#{doc_id}", **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/put-snapshot-repo-api.html
def create_snapshot_repository profile, name, type, settings, **kwargs
  return make_json_request profile, :PUT, "/_snapshot/#{name}",
                           { :type => type, :settings => settings }, **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/7.9/get-snapshot-repo-api.html
def get_snapshot_repositories profile, **kwargs
  return make_request profile, :GET, "/_snapshot", **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/delete-snapshot-repo-api.html
def delete_snapshot_repository profile, repository, **kwargs
  return make_request profile, :DELETE, "/_snapshot/#{repository}", **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/7.9/get-snapshot-api.html
def get_repository_snapshots profile, repository, **kwargs
  return make_request profile, :GET, "/_snapshot/#{repository}/*", **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/create-snapshot-api.html
def create_snapshot profile, repository, wait: true, name: nil, **kwargs
  # Use the default snapshot name template if no name was specified.
  if name == nil
    name = $ES_MANUAL_SNAPSHOT_NAME_TEMPLATE
  end
  # Exclude .security* indices.
  data = { :indices => [ '*', '-.security*' ], :wait => wait }
  return make_json_request profile, :PUT, "/_snapshot/#{repository}/#{name}", data, **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/7.9/restore-snapshot-api.html
def restore_snapshot profile, repository, snapshot, wait: true, **kwargs
  path = "/_snapshot/#{repository}/#{snapshot}/_restore?wait_for_completion=#{wait}"
  return make_request profile, :POST, path, **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/delete-snapshot-api.html
def delete_snapshot profile, repository, snapshot, **kwargs
  return make_request profile, :DELETE, "/_snapshot/#{repository}/#{snapshot}", **kwargs
end

# https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html
def load_bulk_data profile, ndjson_data, **kwargs
  return make_request profile, :POST, "/_bulk",
                      body: ndjson_data,
                      headers: { 'content-type' => 'application/x-ndjson' },
                      **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/slm-api-put-policy.html
def create_snapshot_policy profile, name, data, **kwargs
  return make_json_request profile, :PUT, "/_slm/policy/#{name}", data, **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/slm-api-execute-lifecycle.html
def execute_snapshot_policy profile, policy, **kwargs
  return make_request profile, :POST, "/_slm/policy/#{policy}/_execute"
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/slm-api-get-policy.html
def get_snapshot_policy profile, policy: nil, **kwargs
  path = '/_slm/policy'
  if policy != nil
    path += "/#{policy}"
  end
  return make_request profile, :GET, path, **kwargs
end


# https://www.elastic.co/guide/en/elasticsearch/reference/current/slm-api-delete-policy.html
def delete_snapshot_policy profile, policy, **kwargs
  return make_request profile, :DELETE, "/_slm/policy/#{policy}", **kwargs
end
