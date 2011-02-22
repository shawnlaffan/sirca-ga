# vim: set ts=4 sw=4 et :

package SircaUI::sirca_appender_socket;
#use SircaUI::sirca_client;
use Win32::API::OutputDebugString qw(OutputDebugString);

my @preinit_buffer;

sub new {
    my($class, %options) = @_;

    my $self = { %options };
    $$self{'preinit_buffer'} = []; # for storing messages before a socket is available
    $$self{'socket'} = undef;

    bless $self, $class;
    return $self;
}
sub set_socket {
    my $self = shift;
    $$self{'socket'} = shift;

    # send all buffering messages
    #foreach $msg (@{$$self{'preinit_buffer'}}) {
    foreach $msg (@preinit_buffer) {
        $self->log( message, $msg );
        Win32::API::OutputDebugString::OutputDebugString ( "tried to log $msg" );
    }
    $$self{'preinit_buffer'} = undef;
}
sub log {
    my($self, %params) = @_;
    my $msg = $params{message};

    my $socket = $$self{'socket'};
    if (defined $socket) {
        SircaUI::sirca_client::write_object($socket, { type => 'log_msg', msg => $msg });
    } else {
        #unshift @{$$self{'preinit_buffer'}}, $msg;
        push @preinit_buffer, $msg;
    }
}

1;

