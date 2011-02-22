#  perl package to manipulate collections of sirca objects
#  example uses include the collection of statistics across multiple runs.

#
#  need to modify it so it deals with collections of models instead of just
#  single instances of an iteration over a set of repetitions.  

package Sirca::Stats;

use strict;
use warnings;
use English qw ( -no_match_vars );

use base qw /Biodiverse::Statistics/;

#use base qw /Statistics::Descriptive2::Full/;

our $VERSION = 0.1;


sub new {
    my $proto = shift;
    my $label = shift;
    my $class = ref($proto) || $proto;

    my $self = Biodiverse::Statistics->new;

    bless ($self, $class);  #Re-anneal the object
    $self -> set_label ($label);
    return $self;
}

sub get_stats_header {
    my @array = qw /Timestep Label N Min Max Q1 Median Q3 IQR pct5 pct95 Med_to_95 Med_to_05 Skewness Kurtosis/;
    if (wantarray ) {
        return @array, "\n";
    }
    else {
        return join (q{,}, @array) . "\n";
    }
}

sub set_label {
    my $self = shift;
    my $label = shift;

    $self->{label} = $label;

    return;
}

sub get_label {
    my $self = shift;
    return $self->{label};
}

#  get and print the stats for one iteration of a model over a series of repetitions
#  index values default to zero if undef
sub get_stats {
    my $self = shift;
    my %args = @_;
    
    my $model_name = defined $args{name} ? $args{name} : 'noname';
    my $label = $self->get_label;
    my $nodata = -9999;
    
    no warnings 'uninitialized';  # silently treat undef as zero

    my ($Q1, $Q1index) = $self->percentile(25);
    my ($Q3, $Q3index) = $self->percentile(75);
    my ($pct05, $pct05index) = $self->percentile(5);
    my ($pct95, $pct95index) = $self->percentile(95);
    my $IQR = $Q3 - $Q1;
    my $skew = $self -> skewness;
    my $kurt = $self -> kurtosis;
    my $median = $self->count ? $self->median : 0;

    my $line = sprintf (
        "%s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n",
        $model_name,
        $label,
        $self->count,
        $self->min,
        $self->max,
        $Q1,
        $median,
        $Q3,
        $IQR,
        $pct05,
        $pct95,
        $pct95 - $median,
        $median - $pct05,
        (defined $skew ? $skew : $nodata),
        (defined $kurt ? $kurt : $nodata),
    );
    
    return $line;
}

1;

