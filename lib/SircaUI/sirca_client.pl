# vim: set ts=4 sw=4 et :

# This script is launched by the GUI and provides
# the interface for sending jobs to the perl libraries
#
# The GUI creates a listening socket and passes the port
# as a command-line argument to this script. This script
# then connects and sends/receives jobs via YAML documents.
# 
# The YAML documents all end in '...' so that they can be
# delimited
package SircaUI::sirca_client;

use strict;
use warnings;
$| = 1;

use SircaUI::sirca_jobs; # actual implementation of the commands
use SircaUI::sirca_client_log_output;

use IO::Socket::INET;
use IO::Socket;
use IO::Select;
use Carp;
use Storable qw /store retrieve freeze thaw dclone nstore_fd fd_retrieve /;
use Data::Dumper;

use YAML::Syck;
	{
		no warnings 'once';
		$YAML::Syck::ImplicitBinary = 1;
		$YAML::Syck::ImplicitTyping = 1;
		#$YAML::Syck::SingleQuote = 1;
		#$YAML::Syck::ImplicitUnicode = 1;
	}

use Log::Log4perl qw(get_logger :levels);
Log::Log4perl->init("sirca_client.log.conf");

# send stdout/stderr through log4perl..
tie *STDERR, "SircaUI::sirca_client_log_output";
tie *STDOUT, "SircaUI::sirca_client_log_output";

# logger for this module
my $log = get_logger('Sirca::GUI::SocketClient');   #   Eugene - is this correct?  

# catch die events
$SIG{__DIE__} = sub {
	if($^S) {
	    # We're in an eval {} and don't want log
	    # this message but catch it later
	    return;
	}
	$Log::Log4perl::caller_depth++;
	my $logger = get_logger("");
	$logger->fatal(@_);
	die @_; # Now terminate really
};


sub connect_socket {
	my ($server_host, $server_port) = @_;

	my $sock = new IO::Socket::INET(
		PeerAddr => $server_host,
		PeerPort => $server_port,
		Proto => 'tcp');
	die "$!" unless $sock;
	return $sock;
}

sub write_object {
	my $sock = shift;
	my $obj = shift;

	my $doc = YAML::Syck::Dump( $obj ) . "...\n";
	$sock->write($doc, length($doc));
}

sub test_yaml {
	my $d = { a => 23, b => '343', s => 'haha'};
	my $f = freeze($d);
	$$d{'f'} = $f;

	print YAML::Syck::Dump( $d ) . "...\n";
}

# connect to server
my ($host, $port, $port_logging) = ($ARGV[0], $ARGV[1], $ARGV[2]);

$log->info("connecting to $host:$port");
my $sock = connect_socket($host, $port);

$log->info("connecting to $host:$port_logging (logging)");
my $sock_logging = connect_socket($host, $port_logging);

$log->info("connected");

# give socket to the GUISocket appender
my $appenders = Log::Log4perl->appenders();
$$appenders{'GUISocket'}->set_socket($sock_logging);

# read commands from the socket
my $current_doc = "";
my $buf;
while (defined ($buf = $sock->getline()) ) {
	$log->debug("received: $buf");
	$current_doc .= $buf;
	if ($buf eq "...\n") {
		# parse YAML command
		my $command = YAML::Syck::Load($current_doc);
		$current_doc = '';
		$log->debug("got command: " . Data::Dumper::Dumper($command));

		# execute the command - attempting to handle errors
		my $result;
	    eval { $result = SircaUI::sirca_jobs::handle_job($command) };
		if ($@) {
            my $err = $@;
			$log->error($err);
			$result = { type => 'error', message => $err };
		}
        if ($log->is_debug()) {
    		$log->debug("got result: " . Data::Dumper::Dumper($result));
        }
		write_object($sock, $result);
	}
}

$log->info("connection closed");

1;

