require "net/imap" 
require "yaml" 
require "rest-client" 
require "json"
require "optparse"
require "mail"
require "ostruct"
require "nokogiri"

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
		    imap.fetch(1..counter, ["RFC822","rfc822.size","uid","envelope","body[text]"])
        else
            []
        end
	end

    def get_text_body(msg)
        mm = Mail.read_from_string msg.attr["RFC822"]
        if (mm.text_part)
           mm.text_part.body.to_s
        elsif (mm.html_part) 
           Nokogiri::HTML(mm.html_part.decoded.to_s).text
        else
          Nokogiri::HTML(mm.body.decoded.to_s).text
        end
    end 

    def get_mail_header(msg, header)
        mm = Mail.read_from_string msg.attr["RFC822"]
        mm.header["#{header}"]
    end 

    def move_message(message,destination)
        imap.select(mailbox)
        imap.uid_move(message.attr["UID"],destination)
    end

	private
	
	attr_accessor :imap, :mailbox
end

class JiraService
	def initialize(apiurl:,username:,password:)
		@resource = RestClient::Resource.new(apiurl, user: username, password: password)
	end

	def post_internal_comment(key,commentbody)
		comment_json = {"body"=>commentbody.to_s.force_encoding('UTF-8'), "properties"=>[{"key"=>"sd.public.comment", "value"=>{"internal"=>true}}]}.to_json
		resource["issue/#{key}/comment"].post(comment_json, :content_type => :json)
	end

    def search(jql)        
        # to-do eventually write a proper search, handle large lists properly.
        # for now, a simple GET will work.
        response = resource["search?jql=#{jql}"].get()
        JSON.parse(response, object_class: OpenStruct)
    end 

	private 

	attr_accessor :resource
end

def unpack_b_or_q(s_text) 

    if m = /=\?([A-Za-z0-9\-]+)\?(B|Q)\?([!->@-~]+)\?=/i.match(s_text)
        case m[2]
        when "B" # Base64 
          decoded = Base64.decode64(m[3])
        when "Q" # Q
          decoded = m[3].unpack("M").first.gsub('_',' ')
        else
          decoded =s_text
        end
        decoded.encode('utf-8') # to convert to utf-8
    else
        s_text
    end
end

configfile = ArgsParserValidator.parse(ARGV)
every_email_has_been_posted = true

if (configfile.length > 0)
    config = YAML.load(File.read(configfile)) 

    messagefinder = IMAPService.new(host: config["host"],username: config["username"], password: config["password"], mailbox: config["mailboxfolder"])
    jiraservice = JiraService.new(apiurl: config["jiraurl"], username: config["jirausername"], password: config["jirapassword"])

    messagefinder.messages.each do |msg| 
        match = unpack_b_or_q(msg.attr["ENVELOPE"].subject).to_s.match(/([A-Z]+-\d+).*/u)
        if (!match) 
           jiraid = messagefinder.get_mail_header(msg, "in-reply-to").to_s.split('.')
           if jiraid[0] == "\<JIRA"
               jirares = jiraservice.search("id=#{jiraid[1]}") 
               if (jirares.total > 0) 
                   match = ["",jirares.issues[0].key]
               end
           end
        end 
        next unless match
        issuekey = match[1]
        begin
            from = msg.attr["ENVELOPE"].from[0]
            thatfromfield = "#{from.name} #{from.mailbox}@#{from.host}"
            textbody = messagefinder.get_text_body(msg)
            jiraservice.post_internal_comment(issuekey,"From: #{thatfromfield}\nDate:#{msg.attr["ENVELOPE"].date}\n\n#{textbody}")
            messagefinder.move_message(msg,config["destmailbox"])
        rescue StandardError => e
            every_email_has_been_posted = false
            puts "Couldn't post comment to JIRA ticket! Issue key: #{issuekey}"
            puts e.message
        end
    end
end

exit 1 unless every_email_has_been_posted
