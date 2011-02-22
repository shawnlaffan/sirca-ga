package Biodiverse::Statistics;

use strict;
use warnings;

our $VERSION = 0.15;

use Carp;

use POSIX qw ( ceil );

use Statistics::Descriptive;
use base qw ( Statistics::Descriptive::Full );

##Create a list of fields not to remove when data is updated
my %fields = (
  _permitted => undef,  ##Place holder for the inherited key hash
  data       => undef,  ##Our data
  presorted  => undef,  ##Flag to indicate the data is already sorted
  _reserved  => undef,  ##Place holder for this lookup hash
);

__PACKAGE__->_make_private_accessors(
    [qw(
        skewness kurtosis
       )
    ]
);
#__PACKAGE__->_make_accessors([qw(presorted _reserved _trimmed_mean_cache)]);


#  same as from Statistics::Descriptive::Full::new
##Have to override the base method to add the data to the object
##The proxy method from above is still valid
sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  # Create my self re SUPER
  my $self = $class->SUPER::new();  
  bless ($self, $class);  #Re-anneal the object
  $self->_clear_fields();
  return $self;
}


sub skewness {
    my $self = shift;

    if (!defined($self->_skewness()))
    {
        my $n    = $self->count();
        my $sd   = $self->standard_deviation();
        
        my $skew;
        
        #  skip if insufficient records
        if ( $sd && $n > 2) {
            
            my $mean = $self->mean();
            
            my $sum_pow3;
            
            foreach my $rec ( $self->get_data ) {
                my $value  = (($rec - $mean) / $sd);
                $sum_pow3 +=  $value ** 3;
            }
            
            my $correction = $n / ( ($n-1) * ($n-2) );
            
            $skew = $correction * $sum_pow3;
        }

        $self->_skewness($skew);
    }

    return $self->_skewness();
}

sub kurtosis {
    my $self = shift;

    if (!defined($self->_kurtosis()))
    {
        my $kurt;
        
        my $n  = $self->count();
        my $sd   = $self->standard_deviation();
        
        if ( $sd && $n > 3) {

            my $mean = $self->mean();
            
            my $sum_pow4;
            foreach my $rec ( $self->get_data ) {
                $sum_pow4 += ( ($rec - $mean ) / $sd ) ** 4;
            }
            
            my $correction1 = ( $n * ($n+1) ) / ( ($n-1) * ($n-2) * ($n-3) );
            my $correction2 = ( 3  * ($n-1) ** 2) / ( ($n-2) * ($n-3) );
            
            $kurt = ( $correction1 * $sum_pow4 ) - $correction2;
        }
        
        $self->_kurtosis($kurt);
    }

    return $self->_kurtosis();
}

#  Snaps percentiles to range 1..100,
#  does not return undef if percentile is < bin size
sub percentile {  
    my $self = shift;
    my $percentile = shift || 0;

    my $count = $self->count;
    return if ! $count; #  no records, return undef
  
    $percentile = 100 if $percentile > 100;
    $percentile = 0   if $percentile < 0;
  
    $self->sort_data() if ! $self->presorted;

    my $num = ($count - 1) * $percentile / 100;
    my $index = int ($num + 0.5);

    #  a bit risky - depends on Statistics::Descriptive internals
    my $val = $self->_data->[$index];
    return wantarray
      ? ($val, $index)
      : $val;
}

sub percentile_RFC2330 {
    my $self = shift;
    return $self->SUPER::percentile (@_);
}

1;

__END__

=head1 NAME

Biodiverse::Statistics - Basic descriptive statistical functions.

=head1 SYNOPSIS

  use Biodiverse::Statistics;
  $stat = Biodiverse::Statistics->new();
  $stat->add_data(1,2,3,4);
  $mean = $stat->skewness();
  $var  = $stat->kurtosis();

=head1 DESCRIPTION

Basic descriptive statistics.
Everything from Statistics::Descriptive::Full but with the
addition of skewness and kurtosis.


=head1 METHODS

=over

=item $stat = Biodiverse::Statistics->new();

Create a new object.

=item $stat->skewness();

Returns the skewness of the data. 
A value of zero is no skew, negative is a left skewed tail,
positive is a right skewed tail. 
This is consistent with Excel.

=item $stat->kurtosis();

Returns the kurtosis of the data.
Positive is peaked, negative is flattened.

=item $x = $stat->percentile(25);

=item ($x, $index) = $stat->percentile(25);

Sorts the data and returns the value that corresponds to the
percentile.

=item $x = $stat->percentile_RFC2330(25);

=item ($x, $index) = $stat->percentile_RFC2330(25);

Sorts the data and returns the value that corresponds to the
percentile as defined in RFC2330.  This is the percentile
method from Statistics::Descriptive::Full.


=back

=head1 REPORTING ERRORS

Use the issue tracker at http://www.purl.org/biodiverse

=head1 COPYRIGHT

Copyright (c) 2010 Shawn Laffan. All rights reserved.  

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

For a full copy of the license see <http://www.gnu.org/licenses/>.

=cut
