# newt
A small ruby app that processes emails from a specific folder in a Google mailbox (via IMAPS) and posts the body of the emails as internal comments in the tickets indicated in the subject of the emails.

The necessary information to connect to the mailbox and to JIRA is stored in a .yaml file that is defined in the .yaml-sample file.

You can run the app by supplying the config file as a parameter as follows:

`bundle exec ruby processJETIemails.rb -f yourownconfigfile.yaml`


She turned me into a newt.

A newt?

I got better...
