require "net/imap"
require "yaml"
require "rest-client"
require "json"

$config = YAML.load(File.read("config.yaml"))
$jiraresource = 	RestClient::Resource.new($config["jiraurl"], user: $config["jirausername"], password: $config["jirapassword"])



def messages() 
	imap = Net::IMAP.new($config["host"], {ssl: true} )
	imap.authenticate('PLAIN',$config["username"],$config["password"])

	imap.select("JETIreplies")
	counter = imap.status("JETIreplies",["MESSAGES"])["MESSAGES"]

	#puts counter

	imap.fetch(1..counter, ["rfc822.size","uid","envelope","body[text]"]).each do |msg| 
	subject=msg.attr["ENVELOPE"].subject
	# if match = subject.match("((?<!([A-Za-z]{1,10}/)-?)[A-Z]+-\d+)")
		if match = subject.match(/^([A-Z]+-\d+).*/)
			puts "Found this", match[1]
			yield(match[1],msg.attr["BODY[TEXT]"])
		else
			puts subject
		end
	end
end

def postcomment(key,commentbody)
	comment_json = {"body"=>commentbody, 
		"properties"=>[{"key"=>"sd.public.comment", "value"=>{"internal"=>true}}]}.to_json
	$jiraresource["issue/#{key}/comment"].post(comment_json, :content_type => :json)
end

messages do |issuekey,body| 
	postcomment(issuekey,body)
end
