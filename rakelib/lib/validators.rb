
require 'uri'


###############################################################################
# Validators
###############################################################################

# Return a bool indicating whether a string is valid URL.
# https://stackoverflow.com/questions/1805761/how-to-check-if-a-url-is-valid
$is_valid_url =->(s) {
  begin
    url = URI.parse(s)
  rescue URI::InvalidURIError
    return false
  end
  return (!url.scheme.nil? and !url.hostname.nil? and !url.path.nil?)
}
