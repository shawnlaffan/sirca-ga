package Sirca::Group;

#  package for an individual group (eg a herd or flock)
#  these are pretty much all stored as parameters using the Utilities get/set_param methods

use strict;
use warnings;
use Carp;
use Scalar::Util qw /isweak weaken/;

our $VERSION = 0.1;

use base qw /Sirca::Utilities/;


#  NEED METHODS TO HANDLE NBR MATRICES, INCLUDING HANDLING DELETED GROUPS

sub new {
    my $class = shift;
    my %args = @_;
    
    my $self = bless {}, $class;
    
    #  store the population, but weaken the ref
    $self->set_population (population => $args{population});
    delete $args{population};
    
    $self->set_params (%args);
    
    return $self;
}


sub get_density {
    my $self = shift;
    return $self->get_param ('DENSITY');
}

sub get_density_pct {
    my $self = shift;
    return $self->get_param ('DENSITY_PCT');
}

sub get_density_orig {
    my $self = shift;

    my $dens = $self->get_param ('DENSITY_ORIG');
    if (! defined $dens) {
        $dens = $self->get_density;
        #  assume we're about to change the density, so store this
        $self->set_param (DENSITY_ORIG => $dens);  
    }
    return $dens;
}

sub get_state {
    my $self =  shift;
    return $self->get_param ('STATE');
}

sub set_state {
    my $self = shift;
    $self->set_param (STATE => shift);
    return;
}

sub get_coord_array {
    my $self = shift;
    my %args = @_;
    my $array = $self->get_param ('COORD_ARRAY')
      || croak "Missing COORD_ARRAY parameter\n";

    return wantarray
            ? @$array
            : $array;
}

sub get_current_state {
    my $self = shift;
    my %args = @_;

    return $self->get_state;
}

#  record which population we are part of
#  must be a weakened ref
sub set_population {
    my $self = shift;
    my %args = @_;

    my $pop = $args{population}
      || croak 'No population defined';

    $self->{population} = $pop;

    if (!isweak $self->{population}) {
        weaken $self->{population};
    }

    return;
}

sub get_population {
    my $self = shift;
    
    return $self->{population};
}

sub get_spatial_params {
    my $self = shift;
    my %args = @_;
    
    my $spatial_params = $self->get_param ('SPATIAL_PARAMS');

    if (! defined $spatial_params) {
        my $spatial_conditions = $self->get_param ('NBRHOOD')
                               || $self->get_population->get_param('NBRHOOD');

        $spatial_params = Biodiverse::SpatialParams->new (
            conditions          => $spatial_conditions,
            no_log              => 1,
            keep_last_distances => 1,
        );
        
        #  caching this way could cause grief with mem usage
        $self->set_param (SPATIAL_PARAMS => $spatial_params);
    }

    return $spatial_params;
};

#sub DESTROY {
#    my $self = shift;
#    
#    $self->set_param (PARENT_POPULATION => undef);
#}


1;

