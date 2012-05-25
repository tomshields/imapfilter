ImapFilter v0.8 - readme.txt - 12/19/98

For the latest information about ImapFilter, including the most recent
distribution, please see: http://www.basswood.com/oss/imapfilter/

ImapFilter is a Perl program for filtering an IMAP mailbox according
to a set of rules.  I use ImapFilter to filter my inbox into different
IMAP folders. I also use it for mail folder maintenance, by running
various rules files over each folder periodically. The advantage this
has over other filters (e.g. procmail, mailagent, and zfilter) is that
it is totally independent of the mail delivery.

ImapFilter was originally written by Tom Shields on 4/4/1998

ImapFilter includes the following required packages:
  Net::IMAP by Kevin Johnson <kjj@pobox.com>
  Date::Parse by Graham Barr <Graham.Barr@pobox.com>

Contributions to ImapFilter are always welcome, and may be emailed to
imapfilter@basswood.com.

QuickStart:

Unpack the distribution in your favorite directory, and ensure that
the ImapFilter file has execute permissions.  Also check the first
line of the file to make sure the perl path is correct.  Also, your
@INC must contain '.' - it usually does.

Copy the lib/sample.imapfilter file to $HOME/.imapfilter, and modify
accordingly.  Documentation is in the file.

Test the program by executing something like:

./imapfilter INBOX lib/list

This should give you a list of the messages in your IMAP INBOX.

If that works, then go ahead and copy imapfilter to some standard
executable location, like /usr/local/bin. Also copy the dependent
modules 'Net', 'Data', 'Date', and 'Time' to your /usr/lib/perl or
equivalent.  Now you should be able to run it from anywhere.

Then create a filter file for your inbox (I call mine
$HOME/.inboxfilter).  Look at lib/sample.inboxfilter for some
ideas. Make sure you create the necessary folders using your mail
client, or the FILE and COPY commands will fail.  Test your filter by
copying a bunch of mail to a test folder, and then running something
like:

imapfilter INBOX.test .inboxfilter

I suggest you turn on DEBUG (in the .imapfilter file) while debugging
- it can be very helpful.  Turn it off when finished, or you'll create
some large debug files.

Once everything is working, have your INBOX filtered every two minutes
by adding a line to your crontab like this:

*/2 * * * * /usr/local/bin/imapfilter INBOX /home/myuser/.inboxfilter

Enjoy!

Major todos:

Standard perl installation
More comprehensive documentation
Allow use as a delivery agent, to avoid cron ugliness
A bunch of features (listed in the imapfilter file)
