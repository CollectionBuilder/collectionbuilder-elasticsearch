
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
