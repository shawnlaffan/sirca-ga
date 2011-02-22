# vim: set ts=4 sw=4 et :
use Win32::API::OutputDebugString qw(OutputDebugString);

package SircaUI::sirca_appender_debugview;

sub new {
    my($class, %options) = @_;

    my $self = { %options };
    bless $self, $class;

    return $self;
}
sub log {
    my($self, %params) = @_;
    Win32::API::OutputDebugString::OutputDebugString ($params{message} );
}

1;

