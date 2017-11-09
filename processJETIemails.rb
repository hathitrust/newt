require "net/imap" 
require "yaml" 
require "rest-client" 
require "json"
require "optparse"

class ArgsParserValidator
    def self.parse(args)
        configfile = ""
        opts = OptionParser.new do |opts|
            opts.banner = "Usage: script [options]"
            opts.separator ""
            opts.separator "Specific options:"
            opts.on("-f","--file filename",String,"Config file for supplying options to this script.") do |f|
                if File.exist?(f)
                    configfile = f
                end
            end
            opts.on_tail("-h","--help", "Show this message") do
                puts opts
                exit
            end
        end 
        opts.parse!(args)
        configfile
    end

end

class IMAPService
	def initialize(host:,username:,password:,mailbox:)
        @imap = Net::IMAP.new(host, {ssl: true} )
		@imap.authenticate('PLAIN',username,password)
		@mailbox = mailbox
	end

	def messages
		imap.select(mailbox)
		counter = imap.status(mailbox,["MESSAGES"])["MESSAGES"]
        if counter > 0
		    imap.fetch(1..counter, ["rfc822.size","uid","envelope","body[text]"])
        else
            []
        end
	end

    def move_message(message,destination)
        imap.select(mailbox)
        imap.uid_move(message.attr["UID"],destination)
    end

	private
	
	attr_accessor :imap, :mailbox
end

class JiraCommenter
	def initialize(apiurl:,username:,password:)
		@resource = RestClient::Resource.new(apiurl, user: username, password: password)
	end

	def post_comment(key,commentbody)
		comment_json = {"body"=>commentbody, "properties"=>[{"key"=>"sd.public.comment", "value"=>{"internal"=>true}}]}.to_json
		resource["issue/#{key}/comment"].post(comment_json, :content_type => :json)
	end

	private 

	attr_accessor :resource
end

configfile = ArgsParserValidator.parse(ARGV)

if (configfile.length > 0)
    config = YAML.load(File.read(configfile)) 

    messagefinder = IMAPService.new(host: config["host"],username: config["username"], password: config["password"], mailbox: config["mailboxfolder"])
    jiracommenter = JiraCommenter.new(apiurl: config["jiraurl"], username: config["jirausername"], password: config["jirapassword"])

    messagefinder.messages.each do |msg| 
        match = msg.attr["ENVELOPE"].subject.match(/^([A-Z]+-\d+).*/)
        next unless match
        issuekey = match[1]
        begin
            jiracommenter.post_comment(issuekey,msg.attr["BODY[TEXT]"])
            messagefinder.move_message(msg,config["destmailbox"])
        rescue RuntimeError => e
            puts "Couldn't post comment to JIRA ticket!"
            puts e.message
        end
    end
end
