# vim: set ts=4 sw=4 et :
package SircaUI::sirca_client_log_output;

use strict;
use warnings;

use Log::Log4perl qw(:easy);

sub TIEHANDLE {
    my $class = shift;
    bless [], $class;
}

sub PRINT {
    my $self = shift;
    $Log::Log4perl::caller_depth++;
    DEBUG @_;
    $Log::Log4perl::caller_depth--;
}


1;
