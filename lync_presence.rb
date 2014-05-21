require 'net/http'
require 'net/https'
require 'uri'
require 'json'
require 'time'

# Authentication configuration
$app_url = 'https://domain.com/ucwa/oauth/v1/applications'
$auth_url = 'https://domain.com/WebTicket/oauthtoken'
$user_name = IO.readlines('tech_status.config')[0].chomp
$password = IO.readlines('tech_status.config')[1].chomp
$auth_config = 'auth.config'

$time = Time.new()

# User list to check presence on. Do not
# send a request for more than 50 users 
# at a time. UCWA does support batch requests 
# which may speed up this process.
class Groups
  def self.lync_users
    helpdesk_group = %W[
    	lync.user@domain.com
    	lync.user@domain.com
    ]
  end
end

# Get Auth Token
def get_auth
	uri = URI.parse($auth_url)
	https = Net::HTTP.new(uri.host, uri.port)
	https.use_ssl = true
	request = Net::HTTP::Post.new(uri.path)
	request.body = 'grant_type=password&username=' + $user_name + '&password=' + $password
	response = https.request(request).body
	parsed = JSON.parse(response)
	$auth_token = parsed['access_token']

	# Dump auth token and expiration
	expired = parsed['expires_in']

	File.open($auth_config, 'w') { |file| file.puts $auth_token }
	File.open($auth_config, 'a') { |file| file.puts expired }
	File.open($auth_config, 'a') { |file| file.puts $time }

	return $auth_token
end

# Check if stored auth token is expired
# If expired call get_auth to generate a
# valid token
def get_stored_auth
$store_auth = IO.readlines($auth_config)[0]
	store_expired = IO.readlines($auth_config)[1]
	store_time = IO.readlines($auth_config)[2]
	store_time = Time.parse(store_time)
	expired_time = (store_time + store_expired.to_i)

	if ($time > expired_time)
		get_auth
	else
		$auth_token = $store_auth
		return $auth_token
	end
end

# Create application within Lync
def build_app(app_url, auth_token)
	uri = URI.parse(app_url)
	https = Net::HTTP.new(uri.host, uri.port)
	https.use_ssl = true
	request = Net::HTTP::Post.new(uri.path, initheader = {'Authorization' => 'Bearer ' + auth_token, 'content-type' => 'application/json'})
	
	# Made up stuff
	# Your sys admin may care about the content here
	request.body = {
	    'culture' => 'en-us',
	    'endpointId' => '1235637',
	    'userAgent' => 'RubyApp/1.0 (SomeOS)'
	}.to_json
	response = https.request(request)

	return response
end

# If auth_config is missing then we 
# need to get_auth and generate a token
if File.file?($auth_config)
	build_app($app_url, get_stored_auth)
else
	build_app($app_url, get_auth)
end

# Create group array for later
$user_array = Array.new

# Get user status
Groups.lync_users.each { |lync_user|
	people_url = 'https://domain.com/ucwa/oauth/v1/applications/102123759658/people/' + lync_user + '/presence'
	uri = URI.parse(people_url)
	https = Net::HTTP.new(uri.host, uri.port)
	https.use_ssl = true
	request = Net::HTTP::Get.new(uri.path, initheader = {'Authorization' => 'Bearer ' + $auth_token})
	response = https.request(request).body
	parsed_status = JSON.parse(response)
	parsed_status = parsed_status['availability']

	# Convert email addresses to full names
	def convert_name(lync_user)
	  lync_user = lync_user.split('@').first
	  first_name = lync_user.split('.').first.capitalize
	  last_name = lync_user.split('.').last.capitalize
	  lync_user = first_name + ' ' + last_name
	end

	# Populate array with user status
	$user_array.push('label' => convert_name(lync_user), 'value' => parsed_status)
}

# Returned results should be in this format
# Lync User => Available
# Second User => Away
puts $user_array