#!perl
#
package Sirca::Population;

#  handle a collection of Sirca::Groups as a single connected population (essentially a metapopulation)

use strict;
use warnings;

use English qw { -no_match_vars };

#use Math::Random::MT::Auto qw /get_state rand shuffle srand/;
use GD;  #  the GD library is needed to generate images.
use GD::Simple;

use POSIX qw /fmod/;
use File::Path;
use File::Spec::Functions;
use File::Basename;
use Time::HiRes qw{time};
use Data::Dumper qw /Dumper/;
$Data::Dumper::Sortkeys = 1;
use Carp;
use Scalar::Util qw /blessed/;
use File::Spec;
use Math::Trig;
use Readonly;


use Biodiverse::Index;
use Biodiverse::SpatialParams;
use Sirca::Group 0.1;

use base qw /Sirca::Utilities/;

our $VERSION = 0.1;

Readonly my $comma       => q{,};
Readonly my $null_string => q{};

my %propagation_values = (  #  default state values for propagation
    propstate   => 2,  #  propagating state
    latentstate => 1,   #  new state after transmission/propagation
    suscstate   => 0,  #  susceptible state
    immunestate => 3,
);

my %default_system_values = (  # default system values.  Needs to be fleshed out.
                              #  could be used to define options for the GUI
    DEATHINSTATE      => 2,
    TIMESTEP          => 0,
    DEFAULTSTATE      => 0,  # default state is 0 (the first in the list) unless set in the arguments file
    LABEL             => 'model_',
    OUTPUTDIR         => '.',
    BANDWIDTH         => 1000,
    OUTSUFFIX         => 'fmd',
    OUTSUFFIX_YAML    => 'fmdy',
    PROP_STATES       => {%propagation_values},  #  need to use a copy, not a ref
    IMAGE_CELLSIZE    => 1000,  #  for display
    JOIN_CHAR         => q{:},
    SNAP_STATE_COORDS => 1,  #  should we snap the coords in the state file to the nearest group?
);

sub new {  #  generate a new sirca population object
    my $class = shift;
    my %args = @_;
    
    my $self = {};
    
    bless $self, $class;

    $self->set_params (%default_system_values);

    $self->{GROUPS} = {};
    $self->{STATES} = {};

    # try to load an existing file
    if (defined $args{file}) {
        my $file_loaded = eval {$self -> load_file (@_)};
        return $file_loaded;
    }
    
    #  we're still here so it must need to be built
    $self -> set_params (%args);

    if (exists $args{control_files}) {
        #  parse the relevant files
        foreach my $args_file (@{$args{control_files}}) {
            my $args_f = File::Spec->rel2abs($args_file);
            print "Loading params from $args_f\n";
            $self -> load_params (file => $args_f);
        }
    }
    elsif (exists $args{params_hash}) {
        $self -> set_params (%{$args{params_hash}});
    }
    else {
        croak "Didn't get control_files nor a params_hash! (or grammar lessons)";
    }
    
    print 'Working on object ' . $self -> get_param ('LABEL') . "\n";

    $self -> process_args;  #  do some checks and setup based on the arguments
    #  now read in the population density files and start states
    my $dens_files = $args{density_files} || $self -> get_param ('DENSITY_FILES');
    $self -> read_data_files (files => $dens_files);
    
    
    #  build the spatial index
    my $b = $self -> get_param ('BANDWIDTH') * 2;
    my @res = ($b, $b);  #  CLUNKY
    my $sp_index = Biodiverse::Index -> new (
        parent       => $self,
        resolutions  => \@res,
        element_hash => scalar $self -> get_groups_as_hash,
    );
    
    $self -> set_param (SPATIAL_INDEX => $sp_index);
    
    #  and now set up the search blocks (may remove later, but it depends on how complex we allow the nbrs to be)
    my $search_blocks = $self -> get_param ('INDEX_SEARCH_BLOCKS');
    if (! defined $search_blocks) {
        my $max_nbrhood = $self -> get_param ('MAXNBRHOOD');

        my $log_text
          = $self -> get_param ('LABEL')
          . ": Determining index search blocks using maximum search nbrhood, "
          . "$max_nbrhood\n";
        
        $self -> update_log (text => $log_text);
        my $sp_params = Biodiverse::SpatialParams -> new (conditions => $max_nbrhood);
        $search_blocks = $sp_index -> predict_offsets (spatial_params => $sp_params);
        $self -> set_param (INDEX_SEARCH_BLOCKS => $search_blocks);  #  cache it
    }
    
    return $self;
}

#  run a cull over a set of groups
#  may need a PC term for this...
sub do_event_cull {
    my $self = shift;
    my %args = @_;
    
    my $num_to_do = $args{count};  #  undef means all
    my $fraction = defined $args{fraction} ? $args{fraction} : 1;

    defined $args{state}
      || croak "cull state not specified\n";  #  need to allow this to be any number of states

    my $target_state = $args{state};

    return if defined $num_to_do && $num_to_do <= 0;

    my $min_thresh = defined ($args{min_dens})
                    ? $args{min_dens}
                    : 0;  #  default to 0
    my $max_thresh = defined ($args{max_dens})
                    ? $args{max_dens}
                    : 1;  #  default to 1

    my $min_x = $args{min_x};  #  as with the rand_state_change we need to allow the neighbourhood definitions
    my $max_x = $args{max_x};
    my $min_y = $args{min_y};
    my $max_y = $args{max_y};

    my $rand = $self -> get_param ('RAND_OBJECT');  #  do them in random order
    my $random_list_ref = [keys %{$self->get_groups_at_state (state => $target_state)}];
    my $available = scalar @$random_list_ref;
    $num_to_do = $available if ! defined $num_to_do;
    
    $self -> update_log (
        text => (
            $self -> get_param ('LABEL')
            . ": Culling $num_to_do group"
            . ($num_to_do > 1 ? 's' : $null_string)
            . " of $available in state $target_state\n"
        )
    );
    if ($min_thresh > 0 || $max_thresh < 1) {
        $self -> update_log (
            text => "\t\tDensity thresholds: $min_thresh, $max_thresh\n"
        );
    }

    my $updated = 0;
    while ($updated < $num_to_do) {
        #  randomly select a cell to update
        my $group_id = shift @$random_list_ref;
        last if ! defined $group_id;  #  we've run out of groups
        my $gp_ref = $self -> get_group_ref (group => $group_id);
        my $density_pct = $gp_ref -> get_density_pct;
        next if (   $density_pct <= $min_thresh
                 || $density_pct  > $max_thresh);

        #  now check if it fits the bounding coords
        my ($x, $y) = $gp_ref -> get_coord_array;
        next if defined $min_x and $x < $min_x;
        next if defined $max_x and $x > $max_x;
        next if defined $min_y and $y < $min_y;
        next if defined $max_y and $y > $max_y;
        
        my $bodycount = $self -> get_bodycount (
            group         => $group_id,
            fraction      => $fraction,
            use_orig_dens => $args{use_orig_dens},
        );
        
        $self -> schedule_group_event (
            group     => $group_id,  
            source    => 'CULL',
            bodycount => $bodycount,
            type      => 'group_cull',
        );
        $updated++;
    }
    $self -> update_log (
        text => $self -> get_param ('LABEL')
                . "Scheduled cull (fraction $fraction) of $updated of "
                . "$available groups (target was $num_to_do)\n"
    );

    return;
}

#  change this set of groups to the immune state
sub do_event_vaccinate {
    my $self = shift;
    my %args = @_;
    #   set the state of a set of groups to be the immunestate
    
    #  need to handle the spatial params definition WRT the spatial index
    #  set a flag to use the spatial index or not
    #  flag can be the maximum distance if using complex params (eg an annulus)
    
    #  and now set up the search blocks (may generalise to own sub, as this applies to most global events)
    my $search_blocks;
    my $max_nbrhood = $args{maxnbrhood};
    #  could put an option in to check the complexity of the definition.  if simple then use the index
    if (defined $max_nbrhood) {  #  we can search using the index
        $self -> update_log (text => ($self -> get_param ('LABEL') . ": Determining index search blocks using maximum search nbrhood, $max_nbrhood\n"));
        my $max_nbrhood_sp_params = Biodiverse::SpatialParams -> new (conditions => $max_nbrhood);
        my $sp_index = $self -> get_param ('SPATIAL_INDEX');
        $search_blocks = $sp_index -> predict_offsets (spatial_params => $max_nbrhood_sp_params);
    }
    
    return;
}

#  change the state of a set of groups
#  should really allow the specification of neighbours around a centre coord to make it fully flexible
sub do_event_state_change {
    my $self = shift;
    my %args = @_;
    
    my $new_state = defined ($args{state})
                ? $args{state}
                : $self -> get_param ('DEFAULTSTATE');

    my $min_thresh = defined ($args{min_dens})
                    ? $args{min_dens}
                    : 0;  #  default to 0
    my $max_thresh = defined ($args{max_dens})
                    ? $args{max_dens}
                    : 1;  #  default to 1
    
    my $min_x = $args{min_x};
    my $max_x = $args{max_x};
    my $min_y = $args{min_y};
    my $max_y = $args{max_y};    

    $self -> update_log (
        text => $self -> get_param ('LABEL')
              . ": Updating groups to state $new_state\n"
    );
    if ($min_thresh > 0 || $max_thresh < 1) {
        $self -> update_log (
            text => "\t\tDensity thresholds: $min_thresh, $max_thresh\n"
        );
    }

    my @groups = $self->get_groups;
    my $available = scalar @groups;
    
    my $updated = 0;
    while (my $group_id = shift @groups) {

        last if ! defined $group_id;  #  we've run out of groups

        my $gp_ref = $self -> get_group_ref (group => $group_id);
        my $density_pct = $gp_ref -> get_density_pct;
        
        next if    $density_pct <= $min_thresh
                || $density_pct >  $max_thresh;

        #  now check if it fits the bounding coords
        my ($x, $y) = $gp_ref -> get_coord_array;
        next if defined $min_x and $x < $min_x;
        next if defined $max_x and $x > $max_x;
        next if defined $min_y and $y < $min_y;
        next if defined $max_y and $y > $max_y;
        
        $self -> schedule_group_event (
            group  => $group_id,  
            state  => $new_state,
            source => 'STATE_CHANGE',
            type   => 'update_group_state',
        );
        $updated++;
    }

    $self -> update_log (
        text => "Scheduled $updated of $available groups to change to "
                . "state $new_state in this timestep\n",
    );

    return;
}


#  randomly change the state of a set of groups
#  should really allow the specification of neighbours around a centre coord to make it fully flexible
sub do_event_rand_state_change {
    my $self = shift;
    my %args = @_;
    
    my $new_state = defined ($args{state})
                ? $args{state}
                : $self -> get_param ('DEFAULTSTATE');
    my $num_to_do = defined ($args{count}) 
                ? $args{count}
                : 0;   #  default to nothing

    return if $num_to_do <= 0;
    
    my $min_thresh = defined ($args{min_dens})
                    ? $args{min_dens}
                    : 0;  #  default to 0
    my $max_thresh = defined ($args{max_dens})
                    ? $args{max_dens}
                    : 1;  #  default to 1

    my $min_x = $args{min_x};
    my $max_x = $args{max_x};
    my $min_y = $args{min_y};
    my $max_y = $args{max_y};    

    $self -> update_log (
        text => $self -> get_param ('LABEL') . ": Randomly updating $num_to_do group" .
                ($num_to_do > 1 ? 's' : $null_string) .
                " to state $new_state\n"
    );
    if ($min_thresh > 0 || $max_thresh < 1) {
        $self -> update_log (
            text => "\t\tDensity thresholds: $min_thresh, $max_thresh\n"
        );
    }

    my $rand = $self -> get_param ('RAND_OBJECT');
    my $random_list_ref = $rand -> shuffle ([$self->get_groups]);
    my $available = scalar @$random_list_ref;

    my $updated = 0;
    while ($updated < $num_to_do) {
        #  randomly select a cell to update
        my $group_id = shift @$random_list_ref;
        
        last if ! defined $group_id;  #  we've run out of groups
        
        my $gp_ref = $self -> get_group_ref (group => $group_id);
        my $density_pct = $gp_ref -> get_density_pct;
        
        next if    $density_pct <= $min_thresh
                || $density_pct >  $max_thresh;

        #  now check if it fits the bounding coords
        my ($x, $y) = $gp_ref -> get_coord_array;
        next if defined $min_x and $x < $min_x;
        next if defined $max_x and $x > $max_x;
        next if defined $min_y and $y < $min_y;
        next if defined $max_y and $y > $max_y;
        
        $self -> schedule_group_event (
            group  => $group_id,  
            state  => $new_state,
            source => 'RAND_STATE_CHANGE',
            type   => 'update_group_state',
        );
        $updated++;
    }
    $self -> update_log (
        text => "Scheduled $updated of $available groups to change to "
                . "state $new_state in this timestep "
                ."(target was $num_to_do)\n",
    );

    return;
}

sub get_groups_at_state {  #  returns a hash of groups in a specified state
    my $self = shift;
    my %args = @_;
    my $state = $args{state};
    
    croak "state not specified\n" if ! defined $state;
    
    $self->{STATES}{$state} = {} if ! defined $self->{STATES}{$state};
    
    return wantarray ? %{$self->{STATES}{$state}} : $self->{STATES}{$state};

    return;
}

sub get_group_count_at_state {
    my $self = shift;
    my $hash_ref = $self -> get_groups_at_state (@_);
    
    return scalar keys %$hash_ref;
}

sub get_groups {
    my $self = shift;
    return wantarray ?  keys %{$self->{GROUPS}} : [keys %{$self->{GROUPS}}];
}

#  get a ref to the groups hash
sub get_groups_as_hash {
    my $self = shift;
    
    return wantarray ? %{$self->{GROUPS}} : $self->{GROUPS};
}


#  get a ref to an individual group
sub get_group_ref {
    my $self = shift;
    my %args = @_;
    
    #  croak if not existing
    croak "Group does not exist\n"
      if ! defined $args{group} or ! exists $self->{GROUPS}{$args{group}};

    return $self->{GROUPS}{$args{group}};
}

#  get a list of all the group refs
sub get_group_refs {
    my $self = shift;
    my %args = @_;
    
    my @refs = values %{$self->{GROUPS}};

    return wantarray ? @refs : \@refs;
}


sub group_exists {
    my $self = shift;
    my %args = @_;
    #croak "group not specified" if ! defined $args{group};
    return exists $self->{GROUPS}{$args{group}};
}

sub changed_this_iter {
    my $self = shift;
    my %args = @_;
    return (exists $self->{CHANGEDTHISITER}{$args{group}})
            ? 1
            : 0;
}

sub track_changed_this_iter {
    my $self = shift;
    my %args = @_;
    
    $self->{CHANGEDTHISITER}{$args{group}} ++;
    
    return;
}

#  clear one if a group is specified, otherwise clear the lot
sub clear_changed_this_iter {
    my $self = shift;
    my %args = @_;
    
    if (defined $args{group}) {
        delete $self->{CHANGEDTHISITER}{$args{group}};
    }
    else {
        $self->{CHANGEDTHISITER} = {};
    }
    
    return;
}

sub get_changed_this_iter {
    my $self = shift;
    
    #  make it an empty hash by default
    $self->{CHANGEDTHISITER} = {} if ! defined $self->{CHANGEDTHISITER};
    
    return wantarray ? %{$self->{CHANGEDTHISITER}} : $self->{CHANGEDTHISITER};
}

sub run {  #  run the model for $some number of iterations
    my $self = shift;
    my %args = @_;
    
    my $rand = $self -> get_param ('RAND_OBJECT');
    
    my $start_iter = $self -> get_param('TIMESTEP') + 1;  #  makes iter 0 the start conditions, then first run is iter 1
    my $end_iter = $self -> get_param('TIMESTEP') + ($args{iterations} || 1);
    
    my $transmissions_count = 0;
    my $bodycount = 0;
    my @image_files;
    
    for (my $i = $start_iter; $i <= $end_iter; $i++) {
        #printf "TIMESTEP %4i", $i;
        $self -> set_param (TIMESTEP => $i);

        #  the transition rules are:
        #  2 (infectious) can infect 0 (susceptible) to make it a 1 (latent).
        #  The cells otherwise cycle through the states
        #  given the time periods specified in TRANSITIONS

        #  run the events here
        $self -> run_global_events;  #  run scheduled events
        $self -> run_group_events;

        my $time = time();
        my $t = $self -> run_interactions;
        $transmissions_count += $t || 0;
        $self->{TIMES}{proptime} += (time() - $time);
        $bodycount += $self -> run_mortality;

        $self -> print_state_stats;
        $self -> write_state_stats;  #  NEED TO MODIFY FOR GUI
        if ($self -> get_param ('WRITE_IMAGE')) {  #  NEED TO MODIFY FOR GUI
            push @image_files, $self -> write_image (
                timestep => $i,
                image    => $self -> to_image
            );
        }
        $self -> clear_state_changed;
        $self -> clear_changed_this_iter;

        if ($self -> sum_groups_at_nondefault_states == 0 && $i < $end_iter) {
            print "No more cells with non-zero states, stopping.\n";
            return 1;
        }
    }

    #  need to store this, just in case
    $self -> set_param (RAND_CURRENT_STATE => scalar $rand -> get_state);
    my %summary = (
        TRANSMISSION_COUNT => $transmissions_count,
        BODY_COUNT         => $bodycount,
        IMAGE_FILES        => \@image_files,
    );
    return wantarray ? %summary : \%summary;
}

sub rerun {  #  rerun an already calibrated model based on the group events.
    my $self = shift;
    my %args = @_;
    
    my $end_iter = $args{iterations} || $self -> get_param ('ITERATIONS');
    
    my $transmissions_count = 0;
    my $event_count = 0;
    my @image_files;
    
    for (my $time = 0; $time <= $end_iter; $time++) {
        
        #  run the events here
        $self -> set_param (TIMESTEP => $time);
        $event_count += $self -> run_group_events (timestep => $time);

        $self -> clear_state_changed;
        $self -> print_state_stats;
        $self -> write_state_stats;
        if ($self -> get_param ('WRITE_IMAGE')) {  #  NEED TO MODIFY FOR GUI
            push @image_files, $self -> write_image (
                timestep => $time,
                image => $self -> to_image
            );
        }
    }

    my %summary = (
        EVENT_COUNT => $event_count,
        IMAGE_FILES => \@image_files,
    );

    return wantarray ? %summary : \%summary;
}

sub clear_state_changed {  # clean up the flag tracking state changes this iter
    my $self = shift;
    $self->{CHANGED_STATE_THIS_ITER} = undef;
    
    return;
}

sub track_state_changed {
    my $self = shift;
    my %args = @_;
    my $group_id = $args{group};
    
    warn "state changed more than once for $group_id\n"
      if $self->{CHANGED_STATE_THIS_ITER}{$group_id};
    
    $self->{CHANGED_STATE_THIS_ITER}{$group_id} ++;
    
    return;
}

sub changed_state_this_iter {
    my $self = shift;
    my %args = @_;

    return (exists $self->{CHANGED_STATE_THIS_ITER}{$args{group}})
            ? 1
            : 0;
}

sub calc_next_state {
    my $self = shift;
    my %args = @_;
    my $state = $args{state} || $self->get_param('DEFAULTSTATE');

    return ($state == $self -> get_param('MAX_STATE'))
            ? 0
            : 1 + $state;
}

#  spread the disease
sub run_interactions {
    my $self = shift;
    my %args = @_;
    
    my $bandwidth = $self -> get_param('BANDWIDTH');
    my %prop_vals = %{$self -> get_param ('PROP_STATES')};

    my $interact_function
      =  $self -> get_param('INTERACT_FUNCTION')
      || 'interact_distance';

    #  get the list of infectious cells in random order
    my %infectious_groups
      = $self -> get_groups_at_state (state => $prop_vals{propstate});

    #  return if nothing to propagate
    return 0 if (scalar keys %infectious_groups == 0);  

    #  get the rand object for random numbers
    my $rand = $self -> get_param ('RAND_OBJECT');

    #  randomly order the list
    my $rand_infectious_list_ref = $rand -> shuffle ([sort keys %infectious_groups]);

    #  cache nbrs unless told not to (gives faster processing)
    my $cache_nbrs = $self -> get_param ('CACHE_NBRS');
    $cache_nbrs = 1 if ! defined $cache_nbrs;  

    #  track the number of transmission events
    my $transmission_count = 0;

    #  now loop over the set of infectious groups and evaluate the
    #  disease propagation to their neighbours
    INFECTIOUS_GP:
    foreach my $infectious_gp (@$rand_infectious_list_ref) {
        
        #  get the associated object
        my $infectious_gp_ref = $self -> get_group_ref (group => $infectious_gp);
        my %nbrs = $self -> get_neighbouring_groups (
            group_ref => $infectious_gp_ref,
            cache     => $cache_nbrs
        );

        #  sort by nbrs distance from the infectious group BROKEN FIXMEFIXMEFIXME
        #  not broken now?
        my @nearest = sort { $nbrs{$a} <=> $nbrs{$b} } keys %nbrs;
        my $max_nbr_count_range
          =  $infectious_gp_ref -> get_param ('MAX_NBR_COUNT')
          || $self -> get_param ('MAX_NBR_COUNT');

        #  ignore anything too far away
        if (defined $max_nbr_count_range) {
            my @range = (ref $max_nbr_count_range) =~ /ARRAY/
                        ? @$max_nbr_count_range
                        : (0, $max_nbr_count_range);
            my $min = shift (@range);
            my $range = (pop @range) - $min;
            my $num_nbrs_to_use = int ($min + $rand -> rand ($range));
            @nearest = splice (@nearest, 0, $num_nbrs_to_use);
        }
        my $nbr_rand_list_ref = $rand -> shuffle (\@nearest);

        my $max_interact_count
          =  $infectious_gp_ref -> get_param('MAX_INTERACT_COUNT')
          || $self -> get_param('MAX_INTERACT_COUNT');

        my @range = (ref $max_interact_count) =~ /ARRAY/
                    ? @$max_interact_count
                    : ($max_interact_count, $max_interact_count);
        my $min = shift (@range);
        my $range = (pop @range) - $min;
        my $target_interact_count = int ($min + $rand -> rand ($range));

        my $mdl_label = $self -> get_param ('LABEL');

        my $interactions = 0;
        #print "Starting check of neighbours\n";
        BY_NBR:
        foreach my $neighbour (@$nbr_rand_list_ref) {
            #print "Checking neighour $neighbour\n";
            next if (! $self -> group_exists (group => $neighbour));  #  skip it if it does not exist
            my $nbr_gp_ref = $self -> get_group_ref (group => $neighbour);
            next if $nbr_gp_ref -> get_density == 0;
            
            $interactions ++;
            
            # already changed this iteration (eg from cured to susceptible), so skip it
            next BY_NBR
              if $self -> changed_state_this_iter (group => $neighbour);
            
            my $nbr_state = $nbr_gp_ref -> get_state;
            $nbr_state = $self -> get_param ('DEFAULT_STATE') if ! defined $nbr_state;
            
            #  skip non-susceptibles. In future versions we might increase the
            #  latency fraction instead of skipping
            next BY_NBR
              if $nbr_state != $prop_vals{suscstate};  
            
            my $distance_apart = $nbrs{$neighbour};
            
            #  get the probability of an infection
            my $joint_prob = eval {
                $self -> $interact_function (
                    infectious_gp => $infectious_gp_ref,
                    nbr_gp        => $nbr_gp_ref,
                    bandwidth     => $bandwidth,
                    distance      => $distance_apart,
                );
            };
            croak $EVAL_ERROR if $EVAL_ERROR;

            if ($rand -> rand < $joint_prob) {
                $self -> update_group_state (
                    group => $neighbour,
                    state => $prop_vals{latentstate},
                    source => $mdl_label,
                );
                #print "Incrementing transmission count $transmission_count\n";
                $transmission_count ++;
            }
            last BY_NBR if $interactions >= $target_interact_count;
        }
    }
    #print "Transmission count is $transmission_count\n";
    return $transmission_count;
}

#  product of densities (as %) weighted by kernel
#  (inverse of distance adjusted by bandwidth)
sub interact_distance {
    my $self = shift;
    my %args = @_;
    
    my $joint_dens =
      $args{infectious_gp}->get_density_pct *
      $args{nbr_gp}->get_density_pct;

    my $wt = $args{bandwidth} / $args{distance};

    my $value = $joint_dens * $wt;

    return $value;
}

sub interact_overlap {
    my $self = shift;
    my %args = @_;
    
    my $infectious_gp = $args{infectious_gp};
    my $nbr_gp        = $args{nbr_gp};

    my $joint_dens =
      $infectious_gp->get_density_pct *
      $nbr_gp->get_density_pct;

    my $distance = $args{distance};
    
    my $radius1 = $infectious_gp->get_spatial_params->get_param('INDEX_MAX_DIST');
    my $radius2 = $nbr_gp->get_spatial_params->get_param('INDEX_MAX_DIST');
    
    my $wt = $self->calc_overlap (
        distance => $distance,
        radius1  => $radius1,
        radius2  => $radius2,
    );

    my $value = $joint_dens * $wt;

    return $value;
}

sub calc_overlap {
    my $self = shift;
    my %args = @_;

    my $distance = $args{distance};
    my $radius1  = $args{radius1};
    my $radius2  = $args{radius2};

    my $part1 = $self->get_overlap_cos_part  (@_);
    my $part2 = $self->get_overlap_cos_part  (@_);
    my $part3 = $self->get_overlap_last_part (@_);

    my $intersection = $part1 + $part2 - $part3;

    my $pi = pi;

    my $union        = ($pi * $radius1 ** 2)
                     + ($pi * $radius2 ** 2)
                     - $intersection;

    my $value = eval {$intersection / $union};

    return $value;
}

sub get_overlap_last_part {
    my $self = shift;
    my %args = @_;

    my $distance = $args{distance};
    my $r1       = $args{radius1};
    my $r2       = $args{radius2};

    my $q1 = - $distance + $r1 + $r2;
    my $q2 =   $distance + $r1 - $r2;
    my $q3 =   $distance - $r1 + $r2;
    my $q4 =   $distance + $r1 + $r2;
    
    my $value = 0.5 * sqrt ($q1 * $q2 * $q3 * $q4);
    
    return $value;
}

sub get_overlap_cos_part {
    my $self = shift;
    my %args = @_;

    my $distance = $args{distance};
    my $r1       = $args{radius1};
    my $r2       = $args{radius2};
    
    my $angle = eval {
        $r1 ** 2
            * acos(
                 (  $distance ** 2
                  + $r1 ** 2
                  - $r2 ** 2
                  ) /
                 (2 * $distance * $r1)
                 )
    };

    return $angle || 0;
}

#  calculate position as a % along timeinstate,
#  compare with the positions along the vertices of the piecewise function
sub get_piecewise_value {    
    my $self = shift;
    my %args = @_;
    
    my $position = $args{position};  #  position along the function
    defined $position || croak "position not specified\n";
    
    my $fn = $args{function} || croak "function not specified\n";
    
    my %fn_hash = %$fn;  #  make a copy
    
    return undef if keys %fn_hash == 0;

    my @pieces = sort numerically keys %fn_hash;

    #  find which piece we fall in based on position
    #  for each sub-array, the first value is the position
    my ($left_pos, $right_pos);
    my $snap = 0;
    if (scalar @pieces) {
        if ($position <= $pieces[0]) {  #  to the left - snap it
            $snap = 1;
            $left_pos  = $pieces[0];
            $right_pos = $pieces[0];
        }
        elsif ($position >= $pieces[$#pieces]) {  #  to the right - snap it
            $snap = 2;
            $left_pos  = $pieces[$#pieces];
            $right_pos = $pieces[$#pieces];
        }
        else {
            my $j = $#pieces;
            for my $i (0 .. $#pieces) {
                #  search from the left
                if ($position >= $pieces[$i] && $position <= $pieces[$i+1]) {
                    $left_pos  = $pieces[$i];
                    $right_pos = $pieces[$i+1];
                    last;
                }
                #  and from the right
                elsif ($position >= $pieces[$j-1] && $position <= $pieces[$j]) {
                    $left_pos  = $pieces[$j-1];
                    $right_pos = $pieces[$j];
                    last;
                }
                $j--;
            }
        }
    }
    else {  #  only one position - must be constant
        my $pos = $pieces[0];
        $left_pos  = $fn_hash{$pos};
        $right_pos = $fn_hash{$pos};
    }


    #  get the set of minimum and maximum values
    my @vals;
    my $upper_index = $#{$fn_hash{$left_pos}};  #  get the outer values
    if ($snap) {
        my $pos = $snap == 1 ? $pieces[0] : $pieces[$#pieces];  #  can only be 1 or 2
        $vals[0] = $fn_hash{$pos}[0];
        $vals[1] = $fn_hash{$pos}[$upper_index];
    }
    else {
        #  now we calculate the relative position along this piece of the function
        my $pct_pos = ($position - $left_pos) / ($right_pos - $left_pos);

        my $j = 0; #  ensure we index as 0 and 1
        foreach my $i (0, $upper_index) {
            my $left_val = $fn_hash{$left_pos}[$i];
            my $right_val = $fn_hash{$right_pos}[$i];
            my $val_range = $right_val - $left_val;
    
            #  calculate the value for this position
            #  ((x - min) / (range)) * newrange + newmin
            #  works for any slope.
            #  Min and max values are in the list order, which allows for +ve and -ve slopes
            $vals[$j] = $pct_pos * $val_range + $left_val;
            $j++;
        }
    }
    
    my $rand = $self -> get_param ('RAND_OBJECT');
    #  a random value between the min and the max, as the function returns value in [0,value)
    my $value = $vals[0] + $rand -> rand ($vals[1] - $vals[0]);
    #print "DEBUG:: $bodyCount, $minBodyCount, $maxBodyCount, $self->{GROUPS}{$group_id}{DENSITY}\n";

    return $value;
}

sub construct_death_function {  #  parse the DEATHRATE triplets
    my $self = shift;
    
    my $d_fn = $self -> get_param ('PARSED_DEATH_FUNCTION');
    
    if (! defined $d_fn) {
        my $fn = $self -> get_param ('DEATH_FUNCTION');

        if (! defined $fn) {  # empty function if no params
            return wantarray ? () : {};
        }

        my $d_fn = $self -> parse_piecewise_function (parameters => $fn);

        $self -> set_param (PARSED_DEATH_FUNCTION => $d_fn);
    }
    
    return wantarray ? %$d_fn : $d_fn;
}

#  not sure this is the best structure - might be easier to get the user to define it directly
sub parse_piecewise_function {
    my $self = shift;
    my %args = @_;
    
    my $params = $args{parameters} || [];

    carp "parameters empty in call to parse_piecewise_function\n"
      if ! defined $params;

    my $pc_fn = {};
    my $fn;  #  iterator variable 

    #  get the longest set
    my $max_index = 0;
    foreach $fn (@$params) {
        $max_index = $#$fn > $max_index ? $#$fn : $max_index;
    }
    
    foreach $fn (@$params) {
        my $time = $fn->[0];
        foreach my $i (1 .. $max_index) {
            $pc_fn->{$time}[$i-1] = defined $fn->[$i] ? $fn->[$i] : $fn->[$i-1];
        }
    }
    
    return wantarray ? %$pc_fn : $pc_fn;
}

sub get_death_function {
    my $self = shift;
    
    my $fn = $self -> get_param ('PARSED_DEATH_FUNCTION');
    
    $fn = $self -> construct_death_function if ! defined $fn;
    
    return wantarray ? %$fn : $fn;
}

#  apply the death function to those groups that deserve it
#  (that are in the death state)
sub run_mortality {
    my $self = shift;
    
    my $death_state = $self -> get_param ('DEATH_IN_STATE');
    
    return if ! defined $death_state;
    
    my $groups_to_cark_it = $self -> get_groups_at_state (state => $death_state);
    
    my $total_bodycount = 0;
    foreach my $group_id (keys %$groups_to_cark_it) {
        my $bodycount = $self -> get_bodycount (
            group            => $group_id,
            use_orig_density => 1,
        );
        $self -> do_event_mortality (
            group     => $group_id,
            bodycount => $bodycount,
        );
        $total_bodycount += $bodycount;
    }

    return $total_bodycount;
}

#  geta bodycount for culling, mortality and other such events
sub get_bodycount {
    my $self = shift;
    my %args = @_;
    
    my $group_id = $args{group} || croak "group not specified\n";
    
    if (! $self -> group_exists (group => $group_id)) {
        croak "Group $group_id does not exist in do_event_mortality\n";
    }
    
    my $time_step = $self -> get_param('TIMESTEP');
    
    my $bodycount = $args{bodycount};  #  allow an absolute death rate
    
    if (! defined $bodycount) {
        #  get the density we need to work on
        my $gp_ref = $self -> get_group_ref (group => $group_id);
        my $density;
        if ($args{use_orig_density}) {
            $density = $gp_ref -> get_density_orig;
        }
        else {
            $density = $gp_ref -> get_density;
        }
        
        if (defined $args{fraction}) {  #  allow a percentage dead if no absolute count
            $bodycount = $args{fraction} * $density;
        }
        else {  #  otherwise try to get a value from the death function
            my $fn = $self -> get_death_function;
            warn "undefined death function, $group_id\n" if ! defined $fn;
            return 0 if ! defined $fn;
            
            #  need to get a value from the piecewise linear function
            #  first we need our relative position
            
            my $t_last_change = $gp_ref->get_param ('TIME_OF_LAST_STATE_CHANGE');
            my $t_next_change = $gp_ref->get_param ('TIME_OF_NEXT_STATE_CHANGE');
            my $position = ($time_step - $t_last_change) /
                           ($t_next_change - $t_last_change);

            #  assumes value is between 0 and 1
            my $value = $self -> get_piecewise_value (
                function => $fn,  #  need to change this to use max and min functions
                position => $position,
            );

            return 0 if ! defined $value;  #  must be no function defined

            $bodycount = $density * $value;
        }
    }
    
    return $bodycount;
}

#  very similar to do_event_mortality, except it does not store the event (because it should be called as an event)
sub do_event_group_cull {
    my $self = shift;
    my %args = @_;
    
    my $group_id = $args{group} || croak "group not specified\n";
    
    if (! $self -> group_exists (group => $group_id)) {
        croak "Group $group_id does not exist in do_event_group_cull\n";
    }
    
    my $bodycount = $self -> get_bodycount (%args);
    return 0 if $bodycount == 0;  #  don't do anything if the bodycount is zero

    my $building = $self -> get_param ('BUILDING');
    my $time_step = $self -> get_param ('TIMESTEP');
    
    my $gp_ref = $self -> get_group_ref (group => $group_id);
    my $density = $gp_ref -> get_density;
    
    #print "CULLING $group_id, $bodycount, $density\n";
    
    $density -= $bodycount;
    $density = 0 if $density < 0;
    $gp_ref -> set_param (DENSITY => $density);
    $gp_ref -> set_param (DENSITY_PCT => $self->convert_dens_to_pct (value => $density));

    $self -> track_changed_this_iter (group => $group_id);

    if ($building and $density == 0) {
        #  total death.  set it back to the default state
        $self -> update_group_state (
            group => $group_id,
            state => $self -> get_param ('DEFAULT_STATE'),
            timestep => $time_step,
        );
    }

    return $bodycount;
}

sub do_event_mortality {
    my $self = shift;
    my %args = @_;

    my $group_id = $args{group} || croak "group not specified\n";
    
    if (! $self -> group_exists (group => $group_id)) {
        croak "Group $group_id does not exist in do_event_mortality\n";
    }

    my $bodycount = $self -> get_bodycount (%args);  #  allows laziness in the code, as we can handle all the variations this way
    return 0 if $bodycount == 0;  #  don't do anything if the bodycount is zero

    my $building = $self -> get_param ('BUILDING');
    my $time_step = $self -> get_param ('TIMESTEP');
    
    if ($building) {
        #  record the event in the scheduler
        $self -> schedule_group_event ( group => $group_id,
                                        endtime => $time_step,
                                        bodycount => $bodycount,
                                        type => 'mortality'
                                        );
    }
    
    my $gp_ref = $self -> get_group_ref (group => $group_id);
    my $density = $gp_ref -> get_density;
    $density -= $bodycount;
    $density = 0 if $density < 0;
    $gp_ref -> set_param (DENSITY => $density);
    $gp_ref -> set_param (DENSITY_PCT => $self -> convert_dens_to_pct (value => $density));
    
    $self -> track_changed_this_iter (group => $group_id);
    
    if ($building and $density == 0) {
        #  total death.  set it back to the default state
        $self -> update_group_state (group => $group_id,
                                     state => $self -> get_param ('DEFAULT_STATE'),
                                     timestep => $time_step,
                                    );
    }
    
    return $bodycount;    
}


sub calc_time_of_state_change {#  determine how long it will remain in this state as a random function of the time range
    my $self = shift;
    my %args = @_;
    my $group_id = $args{group} || croak "coord not specified\n";
    #croak "No Coordinate specified for calc_time_of_state_change()\n" if ! defined $group_id;
    my $gp_ref = $self -> get_group_ref (group => $group_id);
    my $state = $gp_ref -> get_state;
    $state = $self -> get_param ('DEFAULT_STATE') if ! defined $state;
    
    my $rand = $self -> get_param ('RAND_OBJECT');
    my $timestep = $self -> get_param ('TIMESTEP');
    my $time_of_change = undef;

    my @trans_array = @{$self->get_param('TRANSITIONS')};
    my ($state_time_min, $state_time_max) = @{$trans_array[$state]};
    #  if they are defined then we use them
    if (defined $state_time_min && defined $state_time_max) {
        $state_time_max = $state_time_min if (! defined $state_time_max || $state_time_min > $state_time_max);
        my $time_in_state = int ($state_time_min + $rand -> rand ($state_time_max - $state_time_min));
        print "Successful allocation of max time in state $state_time_max\n" if $state_time_max == $time_in_state;
        
        $time_of_change = $time_in_state + $timestep;
        $gp_ref -> set_param (TIME_OF_NEXT_STATE_CHANGE => $time_of_change);
    }
    else {
        $gp_ref -> set_param (TIME_OF_NEXT_STATE_CHANGE => undef);
    }
    $gp_ref -> set_param (TIME_OF_LAST_STATE_CHANGE => $timestep);
    
    return $time_of_change;
}

#  may not be needed, but allows possibly more logical later calls to update_group_state
sub do_event_update_group_state {
    my $self = shift;
    $self -> update_group_state (@_);
}

sub do_event_increment_state {
    my $self = shift;
    #my %args = @_;
    
    $self -> update_group_state (@_);
}

sub update_group_state {  #  Update the state of a group.
    my $self = shift;
    my %args = @_;
    
    croak "state parameter not specified\n"  if ! defined $args{state};
    croak "group parameter not specified\n" if ! defined $args{group};
    
    my $building = $self -> get_param ('BUILDING');
    
    my $group_id = $args{group};
    my $new_state = $args{state};
    my $source = $args{source};  #  used to record where it came from.  defaults to undef
    my $default_state = $self -> get_param ('DEFAULTSTATE');
    my $current_timestep = $self -> get_param ('TIMESTEP');
    
    #  get the group's current state
    my $gp_ref = $self -> get_group_ref (group => $group_id);
    my $current_state = $gp_ref -> get_state;
    $current_state = $default_state if ! defined $current_state;
    
    #  get the relevant change timings
    my $t_last_state_change = $gp_ref -> get_param ('TIME_OF_LAST_STATE_CHANGE');
    my $prev_t_next_state_change = $gp_ref -> get_param ('TIME_OF_NEXT_STATE_CHANGE');
    
    
    #  update the group's params
    $gp_ref -> set_state ($new_state);
    my $t_next_state_change;
    if ($building) {
        $t_next_state_change = $self -> calc_time_of_state_change (group => $group_id);
        $gp_ref -> set_param (TIME_OF_NEXT_STATE_CHANGE => $t_next_state_change);
    }
    $gp_ref -> set_param (TIME_OF_LAST_STATE_CHANGE => $current_timestep);
    

    #  update self's trackers
    $self->{STATES}{$new_state}{$group_id} ++ if $new_state != $default_state;
    delete $self->{STATES}{$current_state}{$group_id};
    $self -> track_state_changed (group => $group_id);
    $self -> track_changed_this_iter (group => $group_id);
    
    if ($building) {  #  if we're in the first run then we need to schedule some events
        #  cancel the previously scheduled state changes (if they exist)
        #  but only if it scheduled events to occur after this timestep
        #  these are normally due to complete mortality or vaccination
    #    need to check if we are changing the current timestep.  
        if ((defined $prev_t_next_state_change) and $prev_t_next_state_change > $current_timestep) {
            #  check the transition to this state
            if (defined $t_last_state_change) {
                #  go back to the last state change and amend the predicted endtime
                $self -> schedule_group_event ( group => $group_id,
                                                timestep => $t_last_state_change,
                                                endtime => $current_timestep,
                                                type => 'update_group_state'
                                                );
            }
            #  cancel the transition to the next state
            $self -> cancel_group_event (   group => $group_id,
                                            timestep => $prev_t_next_state_change,
                                            type => 'update_group_state',
                                        );
        }
    
        #  now record these events
        #  first we record this event in the schedule
        #  if it already exists then this will put more info onto it
        $self -> schedule_group_event ( group => $group_id,
                                        state => $new_state,
                                        endtime => $t_next_state_change,
                                        source => $source,
                                        timestep => $current_timestep,
                                        type => 'update_group_state',
                                       );
        #  now we schedule the next state change (if there is one)
        if (defined $t_next_state_change) {
            $self -> schedule_group_event ( group => $group_id,
                                            timestep => $t_next_state_change,
                                            state => $self -> calc_next_state (state => $new_state),
                                            type => 'update_group_state',
                                           );
        }
    }
    
    return 1;
}

#  delete cells with negative states or zero densities, or if they happen to annoy you for some reason...
sub delete_group {  
    my $self = shift;
    my %args = @_;
    my $group_id = $args{group} || croak "coord not specified\n";

    return if ! (exists $self->{GROUPS}{$group_id});  #  does not exist anyway...
    
    my $group = $self -> get_group_ref (group => $group_id);
    my $state = $group -> get_state; 

    $self->{GROUPS}{$group_id} = undef;
    delete $self->{GROUPS}{$group_id}; 
    delete $self->{STATES}{$state}{$group_id};
    
    #  delete it from the spatial index (a source of much debugging woe)
    $self -> delete_from_spatial_index (group => $group_id);
    
    ####################
    #  NEED METHODS TO DELETE GROUPS FROM THEIR NBR MATRICES
    
    #  need to delete it from the normal and reversed neighbour matrices as well
    #$self -> delete_from_nbr_matrix;

    #$self->{NBRMATRIX}{$group_id} = undef;
    #delete $self->{NBRMATRIX}{$group_id};
    ##  the reverse may have already been cleared by a previous deletion
    #if (exists $self->NBRMATRIX_REVERSED}{$group_id}) {
    #    #  recalculate nbrs nbrs
    #    foreach my $nbr (keys %{$self->NBRMATRIX_REVERSED}{$group_id}}) {
    #        $self->{NBRMATRIX}{$nbr} = undef;
    #        delete $self->{NBRMATRIX}{$nbr};
    #        $self -> get_neighbours(group => $nbr, 'cache' => 1);
    #    }
    #    $self->NBRMATRIX_REVERSED}{$group_id} = undef;
    #    delete $self->NBRMATRIX_REVERSED}{$group_id};
    #}

    return 1;
}

sub delete_from_spatial_index {
    my $self = shift;
    my %args = @_;
    my $group_id = $args{group} || croak "group not specified\n";
    my $group_ref = $self -> get_group_ref (group => $group_id);
    
    my $index = $self -> get_param ('SPATIAL_INDEX');
    $index -> delete_from_index (element => $group_id, element_array => scalar $group_ref -> get_coord_array);
}

#  delete a coord entry from the neighbour matrix
#sub delete_from_nbr_matrix {
#    my $self = shift;
#    my %args = @_;
#    
#    my $group_id = $args{group} || croak "coord not speficied\n";
# 
#    $self->{NBRMATRIX}{$group_id} = undef;
#    delete $self->{NBRMATRIX}{$group_id};
#    
#    #  the reverse may have already been cleared by a previous deletion, so check to avoid autovivification
#    if (exists $self->NBRMATRIX_REVERSED}{$group_id}) {
#        #  clear and then recalculate nbr's nbrs
#        foreach my $nbr (keys %{$self->NBRMATRIX_REVERSED}{$group_id}}) {
#            $self->{NBRMATRIX}{$nbr} = undef;
#            delete $self->{NBRMATRIX}{$nbr};
#            $self -> get_neighbouring_groups (group => $nbr, cache => 1);
#        }
#        $self->NBRMATRIX_REVERSED}{$group_id} = undef;
#        delete $self->NBRMATRIX_REVERSED}{$group_id};
#    }
#}


#  get the distance to which this coord should be interacting 
#sub get_group_range {
#    my $self = shift;
#    my %args = @_;
#    
#    my $group = $self -> get_group_ref (%args);
#    
#    #  use it if it already exists (@_ should contain the coord arg)
#    my $tmp = $group -> get_value ('RANGE');
#    return $tmp if defined $tmp;
#    
#    #  calculate it if it does not exist and the right params are set
#    
#    my $min_dist = $group -> get_value ('MINNBRDIST') || $self -> get_param ('MINNBRDIST');
#    my $max_dist = $group -> get_value ('MAXNBRDIST') || $self -> get_param ('MAXNBRDIST');
#    my $dens_params = $self -> get_param ('RANGE_DENSITY_PARAMS')
#                   || $self -> get_param ('DENSITYPARAMS');
#    
#    if (! (defined $min_dist && defined $dens_params)) {
#        $group -> set_value ('RANGE' => $max_dist);
#        return $max_dist;
#    }
#    
#    #  subtract the min, divide by the range - converts to a fraction of 1
#    my $dens_pct = ($group -> get_density - $dens_params->[0]) / ($dens_params->[1] - $dens_params->[0]);
#    
#    #  now scale that fraction between the range extrema
#    my $range = ($max_dist - $min_dist) * $dens_pct + $min_dist;
#    
#    $group -> set_value (RANGE => $range);
#
#    return $range;
#}


sub get_neighbouring_groups {  #  uses the spatial index to accelerate the search for neighbours
    my $self = shift;
    my %args = (
        cache => 1,
        @_
    );


    my $central_gp_ref = $args{group_ref}
      || croak "group not specified\n";

    my $nbr_list_name = 'NBRS';
    #  mark nbrs from another object
    $nbr_list_name .= defined $args{label}
                    ? "_$args{label}"
                    : "";  

    my $nbrs = $central_gp_ref -> get_param ($nbr_list_name);
    my $max_nbr_count = $central_gp_ref -> get_param ('MAX_NBR_COUNT')
                        || $self -> get_param ('MAX_NBR_COUNT');

    #  empty hash if we don't want any neighbours
    if ($max_nbr_count == 0) {
        $nbrs = {} ;
    }

    if (defined $nbrs) {
        return wantarray ? %$nbrs : $nbrs;
    }

    my $sp_index = $self -> get_param ('SPATIAL_INDEX');

    my $spatial_params = $central_gp_ref->get_spatial_params;

    my $search_blocks = $self -> get_param ('INDEX_SEARCH_BLOCKS');
    if (! defined $search_blocks) {
        my $max_nbrhood = $self -> get_param ('MAXNBRHOOD');
        $self -> update_log (
            text => ""
                    . $self -> get_param ('LABEL')
                    . ": Determining index search blocks using maximum "
                    . "search nbrhood, $max_nbrhood\n",
        );

        my $max_nbrhood_sp_params = Biodiverse::SpatialParams -> new (
            params => $max_nbrhood,
        );

        $search_blocks =  $self -> predict_offsets (
            spatial_params => $max_nbrhood_sp_params,
        );

        $self -> set_param ('INDEX_SEARCH_BLOCKS' => $search_blocks);  #  cache it
    }
    
    my $central_coords = $central_gp_ref -> get_param ('COORD_ARRAY');
    
    my $nbr_list = $self -> get_neighbours (
        coords         => $central_coords,
        spatial_params => $spatial_params,
        index          => $sp_index,
        index_offsets  => $search_blocks,
        #  one cannot be one's own neighbour
        #  as that would violate the time-space continuum
        exclude_list   => [$central_gp_ref -> get_param ('ID')],
    );

    # now get the nearest however many.  use parameter D for now (absolute distance)
    my %nbrs_with_dist;
    #  I'm sure there's a slice function we can use instead of the loop
    foreach my $nbr (keys %$nbr_list) {
        $nbrs_with_dist{$nbr} = $nbr_list->{$nbr}{D};
    }

    #  now we cache them (if need be)
    if ($args{cache}) {
        $central_gp_ref -> set_param ($nbr_list_name => \%nbrs_with_dist);
        
        #  and let the neighbour keep a track of us (lousy Flanders)
        foreach my $nbr (keys %nbrs_with_dist) {
            my $nbr_gp_ref = $self -> get_group_ref (group => $nbr);
            my $nbr_of_list = 'ISA_NBR_OF_' . $self -> get_param ('LABEL');
            my $nbr_of_ref = $nbr_gp_ref -> get_param ($nbr_of_list);
            if (! defined $nbr_of_ref) {
                $nbr_of_ref = {};
                $nbr_gp_ref -> set_param ($nbr_of_list => $nbr_of_ref);
            }
            #  don't store a ref to it - memory leaks can result
            my $id = $central_gp_ref -> get_param ('ID');
            $nbr_of_ref->{$id} = $nbrs_with_dist{$nbr};
            #print  "";  #  debug hook
        }
    }


    return wantarray ? %nbrs_with_dist : \%nbrs_with_dist;
}




########################################################
#  methods to get neighbours, parse parameters etc.

#  totally flogged from Biodiverse - hence the differing names (element_array1 etc)

sub get_neighbours {  #  get the list of neighbours within the specified distances -
                     #  NOTE we do not handle non-numeric distances at the moment
    my $self = shift;
    my %args = @_;
    my $centre_coord_ref = $args{coords} || croak "argument element not specified\n";
    my $sp_params = $args{spatial_params} || $self -> get_param ('SPATIAL_PARAMS');
    #my $spatialParamsRef = $args{parsed_spatial_params} || return wantarray ? () : {};
    my $index = $args{index};
    
    #  skip those elements that we want to ignore - allows us to avoid including
    #  element_list1 elements in these neighbours,
    #  therefore making neighbourhood parameter definitions easier.
    my %exclude_hash = $self -> array_to_hash_keys (list => $args{exclude_list}, value => 1);

    #my $spatialConditions = $spatialParamsRef->{conditions};
    

    my @compare_list;  #  get the list of possible neighbours
    if (! defined $args{index}) {
        @compare_list = $self -> get_groups;  #  possible source of misery at a later date...
    }
    else {  #  we have a spatial index defined - get the possible list of neighbours
        my $index_coord = $index -> snap_to_index (element_array => $centre_coord_ref);
        foreach my $offset (keys %{$args{index_offsets}}) {
            #  need to get an array from the index to fit with the get_groups results
            push @compare_list, ($index -> get_index_elements_as_array (element => $index_coord,
                                                                       offset => $offset));
        }
    }
    
    my %valid_nbrs;
    NBR: foreach my $element2 (@compare_list) {
        next if ! defined $element2;  #  some of the elements may be undefined based on calls to get_index_elements
        next if exists $exclude_hash{$element2};  #  in the exclusion list
        next if exists $valid_nbrs{$element2};  #  already done this one

        #  make the neighbour coord available to the spatial_params
        my $gp_ref = $self -> get_group_ref (group => $element2);
        my $coord  = $gp_ref -> get_param ('COORD_ARRAY');

        next NBR if ! $sp_params -> evaluate (coord_array1 => $centre_coord_ref,
                                              coord_array2 => $coord);

        # If it has survived then it must be valid.
        $valid_nbrs{$element2} = $sp_params -> get_param ('LAST_DISTS');
    }

    return ! wantarray ? \%valid_nbrs : %valid_nbrs;
}

sub get_neighbours_as_array {
    my $self = shift;
    my @array = sort keys %{$self -> get_neighbours(@_)};
    return wantarray ? @array : \@array;  #  return reference in scalar context
}
    

sub get_distances {  #  calculate the distances between the coords in two sets of elements
                     #  expects refs to two element arrays and the spatial parameters hash
                     #  at the moment we are only calculating the distances - k stuff can be done later

    my $self = shift;
    my %args = @_;

    croak "params argument not specified\n" if ! defined $args{params};
    croak "element_array1 argument not specified\n" if ! defined $args{element_array1};
    croak "element_array2 argument not specified\n" if ! defined $args{element_array2};
    
    #use bignum;  #  try to avoid some precision probs - NO, TOO SLOW
    
    my @element1 = @{$args{element_array1}};
    my @element2 = @{$args{element_array2}};
    my %params = %{$args{params}};
    #my $bd = $self -> get_param ('BASEDATA_REF');
    my @cellsize;
    my $cellsizes = $self -> get_param ('CELL_SIZES') || 1;  #  we don't actually use cell sizes
    @cellsize = @$cellsizes if (ref $cellsizes) =~ /ARRAY/;
    
    my (@d, $sumDsqr, @D);
    my (@c, $sumCsqr, @C);
    my @iters;
    if (! $params{use_euc_distance} && ! $params{use_cell_distance}) {
        # only calculate the distances we need, as determined when parsing the spatial params
        my %all_distances = (%{$params{use_euc_distances}},
                            %{$params{use_abs_euc_distances}},
                            %{$params{use_cell_distances}},
                            %{$params{use_abs_cell_distances}},
                            );
        @iters = keys %all_distances;
    }
    else {
        @iters = (0..$#element1);  #  evaluate all the coords
    }
    foreach my $i (@iters) {
        my $coord1 = $element1[$i];
        my $coord2 = $element2[$i];
        $d[$i] = $coord2 - $coord1;
        if (! defined $coord2 or ! defined $coord1) {
            print "COORDS: $coord1, $coord2\n";
        }
        $D[$i] = abs ($d[$i]);
        $sumDsqr += $d[$i]**2;
        #  won't need these most of the time
        if ($params{use_cell_distance} || $params{use_cell_distances}) {  
            $c[$i] = $d[$i] / $cellsize[$i];
            $C[$i] = abs ($c[$i]);
            $sumCsqr += $c[$i]**2;
        }
    }
    #  use sprintf to avoid precision issues at 14 decimals or so - a bit of a kludge, though. 
    my $D = $params{use_euc_distance}  ? sprintf ("%.10f", sqrt ($sumDsqr)) : undef;
    my $C = $params{use_cell_distance} ? sprintf ("%.10f", sqrt ($sumCsqr)) : undef;
    
    my %hash = (
        d_list => \@d,
        D_list => \@D,
        D      => $D,
        Dsqr   => $sumDsqr,
        C      => $C,
        Csqr   => $sumCsqr,
        C_list => \@C,
        c_list => \@c,
    );

    return ! wantarray ? \%hash : %hash;
}


sub sum_groups_at_nondefault_states {  #  get a count of the non-zero states
    my $self = shift;
    
    my $default_state = $self -> get_param ('DEFAULT_STATE');
    
    my $sum;
    foreach my $state (0 .. $self->get_param('MAX_STATE')) {
        next if $state == $default_state;
        $sum += (keys %{$self -> get_groups_at_state (state => $state)});
    }
    return $sum;
}

sub print_state_stats {
    my $self = shift;
    
    my $s = $null_string;

    $s .= sprintf "%s TIME STEP %4i", $self->get_param('LABEL'), $self->get_param('TIMESTEP');
    foreach my $i (0 .. $self->get_param('MAX_STATE')) {
        $s .= sprintf " %6i :%2i", my $tmp = (keys %{$self->{STATES}{$i}}), $i;
    }
    $s .= "\n";
    #print $s;
    $self -> update_log (text => $s);
}

sub write_state_stats {
    my $self = shift;
    my $file_name = $self->get_param('OUTPFX') . "_STATISTICS.csv";
    #print "WRITING statistics to $file_name\n";

    if (! $self->{STATISTICS_HEADER_WRITTEN}) {
        open (FILE, ">$file_name");
        print FILE "TIMESTEP";
        foreach my $i (0 .. $self->get_param('MAX_STATE')) {
            print FILE ",COUNT_$i,DENSSUM_$i";
        }
        print FILE "\n";
        $self->{STATISTICS_HEADER_WRITTEN}++;
        close FILE;
    }

    open (my $fh, '>>', $file_name);
    print {$fh} $self->get_param('TIMESTEP');
    foreach my $i (0 .. $self->get_param('MAX_STATE')) {
        printf {$fh} (",%i", my $tmp = (keys %{$self -> get_groups_at_state (state => $i)}));
        printf {$fh} (",%.1f", $self->sum_densities_at_state (state => $i));
    }
    print {$fh} "\n";
    close $fh;
    
    return;
}

#  sum the original densities for one of the model states
sub sum_densities_at_state {
    my $self = shift;
    my %args = @_;
    my $state = $args{state};
    croak "state not specified\n" if ! defined $state;

    my $sumInState = 0;
    foreach my $group_id (keys %{$self -> get_groups_at_state (state => $state)}) {
        my $gp_ref = $self -> get_group_ref (group => $group_id);
        $sumInState += $gp_ref -> get_density;
    }
    return $sumInState;
}

#  return the count of GROUPS in a particular state
sub sum_groups_at_state {
    my $self = shift;
    my %args = @_;
    
    my $state = $args{state};
    croak "state not specified\n" if ! defined $state;
    
    my $hash_ref = $self -> get_groups_at_state (state => $state);
    
    my $count = scalar keys %$hash_ref;
    
    return $count;
}

sub process_args {  #  check we have the required arguments
    my $self = shift;
    
    croak "I NEED THE STATE TRANSITIONS FOR MODEL "
        . $self->get_param('LABEL')
        . "\n"
      if ! $self->get_param('TRANSITIONS');
    
    if (! defined $self -> get_param ('DENSITY_FILES')) {
        carp "Parameter DENSITY_FILES not specified\n";
    }
    
    eval {mkpath ($self->get_param('OUTPUTDIR'))};
    if (! -e $self->get_param('OUTPUTDIR')) {
        croak "Unable to create output path " . $self -> get_param('OUTPUTDIR') . " : $@\n";
    }

    $self->set_param(OUTPFX => catfile ($self -> get_param('OUTPUTDIR'),
                                        $self -> get_param('LABEL')
                                        )
                    );  #  platform independent file names
    
    if ($self->get_param('STATESFILE')) {
        $self->set_param('STATESFILES',
                        $self->get_param('STATESFILES') . $self->get_param('STATESFILE')
                       );
        $self->delete_param('STATESFILE');
    }

    
    $self -> construct_death_function;
    
    my @states = @{$self->get_param('TRANSITIONS')};
    $self -> set_param (MAX_STATE => $#states);

    return;
}

sub append_to_names {
    my $self = shift;
    my %args = @_;
    my $addition = canonpath($args{string});
    my $orig_label = $self->get_param('LABEL');
    $self -> set_param ('LABEL', canonpath ($self -> get_param ('LABEL') . $addition));
    $self -> set_param ('OUTPFX', canonpath ($self -> get_param ('OUTPFX') . $addition));
    my $dirpath = dirname ($self -> get_param ('OUTPFX'));
    eval {mkpath ($dirpath)};
    croak "Unable to create output path $dirpath : $@\n" if ($@);
    #print "$addition appended to OUTPFX and LABEL for $orig_label.  Trailing slashes have been stripped\n";
}


sub get_nearest_group {
    my $self = shift;
    my %args = @_;
    
    my $group_id = $args{group};
    croak "coord not specified\n" if ! defined $group_id;

    return $group_id if $self -> coord_exists (group => $group_id);  # already exists, so skip it

    #  get a hash of the neighbours, from which we will take the nearest
    #  passing the args allows higher calls to control caching
    my $nbr_ref = $self->get_neighbours(@_);  

    return undef if ! keys %{$nbr_ref->{BY_COORD}};  #  nothing there
    
    my $dist = @{[sort numerically keys %{$nbr_ref->{BY_DISTANCE}}]}[0];
    my $nearest = @{[sort keys %{$nbr_ref->{BY_DISTANCE}{$dist}}]}[0];

    return $nearest;
}

sub read_data_files {
    my $self = shift;
    my %args = @_;
    
    my @files = (ref $args{files}) =~ /ARRAY/
                ? @{$args{files}}
                : $args{files};

    foreach my $file (@files) {
        $self -> read_data_file (file => $file);
    }
    
}

sub read_data_file {  #  nothing will happen if the file dos not exist, as we will assume all the GROUPS are dealt with through read_state_file()
    my $self = shift;
    my %args = @_;
    
    my $input_file = $args{file} || croak "density file not specified\n";
    $input_file = File::Spec->rel2abs($input_file);
#use Cwd;
#my $dir = getcwd;

    print "Going to read data from $input_file\n";

    croak "Density file $input_file does not exist.\n" if !(-e $input_file);
    open (my $data_fh, '<', $input_file)
      || croak "Could not open density file $input_file.\n";

    my $header_line = <$data_fh>;
    $header_line =~ s/[\n|\r]$//;
    $header_line =~ s/"//g;  #  sort of cheating here to avoid using the text::CSV_XS module, since we don't really need it for this type of data
    $header_line = uc($header_line);  #  uppercase the lot to save trouble later (and hopefully not get into any as a consequence)

    $self -> update_log (text => "Reading data from $input_file\nHeader line is:\n\t$header_line\n");
    
    my @header = split (/[,\s;]/, $header_line);
    my %header_col;
    my $i = 0;
    foreach my $header (@header) {  #  hashes, arrays and variables called "header", with a bit of reuse - confused?
        $header_col{$header} = $i;
        $i++
    }

    if (! (exists $header_col{X} && exists $header_col{Y})) {
        croak "Data file $input_file missing X or Y field.  \nHeaderline is:\n$header_line\n";
    }
    
    if (not exists $header_col{DENSITY}) {
        warn "Data file $input_file is missing the DENSITY field>  This is an issue if this is the main data file...\n"
    }
    
#    my $dens_column = $header_col{DENSITY};
    
    my $join_char = $self -> get_param ('JOIN_CHAR') || ":";
    
    my $coord_count = 0;

    while (<$data_fh>) {
        $_ =~ s/[\n|\r]$//;  #  strip trailing linefeeds and newlines
        next if $_ eq $null_string;
        my @line = split (/[,\s;]/, $_);
        
        my %params;
        @params{@header} = @line;  #  assign columns to headers
        
        #  add 0 to reduce decimal places
        $params{X} += 0;
        $params{Y} += 0;
        my $group_id = join ($join_char, $params{X}, $params{Y});
        
        #  strip out negative densities, as these should not be there in the first
        #  place and are often used to denote noData
        next if (defined $params{DENSITY} && $params{DENSITY} <= 0);  

        my $dens_pct = defined $params{DENSITY}
                        ? $self -> convert_dens_to_pct (value => $params{DENSITY})
                        : undef;
        
        my $group = Sirca::Group -> new (
            %params,
            DENSITY_PCT => $dens_pct,
            COORD_ARRAY => [$line[$header_col{X}], $line[$header_col{Y}]],
            ID          => $group_id,
            population  => $self,
        );
        
        $self -> add_group (group => $group);
        
        #  add to the hash with this state (if non-zero)
        if (defined $params{STATE} && $params{STATE} != $self -> get_param ('DEFAULT_STATE')) {
            $self->{STATE}{$group -> get_state} = $group;
        }
        
        $coord_count++;
    }

    close $data_fh || croak "could not close $input_file\n";
    $self -> update_log (text => "Read $coord_count valid lines from $input_file\n");
    
    return;
}

sub add_group {
    my $self = shift;
    my %args = @_;
    
    croak  'group not defined'
      if ! defined $args{group};

    my $group = $args{group};
    
    #  add to the hash of groups
    $self->{GROUPS}{$group -> get_param ('ID')} = $group;
    
    #  add to the hash with this state (if non-zero)
    if ($group -> get_state) {
        $self->{STATE}{$group -> get_state} = $group;
    }
}

sub convert_dens_to_pct {
    my $self = shift;
    my %args = @_;
    croak "value not defined" if ! defined $args{value};

    my @params = @{$self->get_param('DENSITYPARAMS')};

    my $density_value= $args{value};

    my $probability;
    if ($density_value< $params[0]) {
        $probability = 0
    }
    elsif ($density_value> $params[1]) {
        $probability = 1
    }
    else {
        $probability = ($density_value- $params[0]) / $params[1]
    }
    return $probability;
}



sub get_image_params {  #  define an output image using the cellsize and the X and Y extents.
    my $self = shift;
    
    my (%x_hash, %y_hash);
    my ($x, $y);
    foreach my $gp_ref ($self -> get_group_refs) {
        ($x, $y) = $gp_ref -> get_coord_array;
        $x_hash{$x} ++;
        $y_hash{$y} ++;
    }

    #  get the first and last values from the X and Y hashes
    my @tmp_array;  #  holds sorted values
    @tmp_array = sort numerically keys %x_hash;
    my $minX = shift @tmp_array;
    my $maxX = pop @tmp_array;    
    @tmp_array = sort numerically keys %y_hash;
    my $minY = shift @tmp_array;
    my $maxY = pop @tmp_array;

    my $x_cells = ($maxX - $minX) / $self -> get_param('IMAGE_CELLSIZE');
    my $y_cells = ($maxY - $minY) / $self -> get_param('IMAGE_CELLSIZE');
    
    my %params = (MIN_X => $minX,
                  MAX_X => $maxX,
                  MIN_Y => $minY,
                  MAX_Y => $maxY,
                  IMAGECELLS_X => $x_cells,
                  IMAGECELLS_Y => $y_cells,
                 );

    $self -> set_params (%params);

    return wantarray ? %params : \%params;
}


sub get_density_image {  #  create an image of the density surface to use as a backdrop for write_model_image
    my $self = shift;
    
    my $img = $self -> get_param ('DENSITY_IMAGE');
    return $img if defined $img;
    
    #my $output = $self->getModelOutput;
    my $x = $self -> get_param('IMAGECELLS_X');
    my $y = $self  -> get_param('IMAGECELLS_Y');
    my $density_image = GD::Simple -> new ($x, $y);

    for (my $i = 0; $i <= 255; $i+=5) {  #  don't fill the whole image colour index
        $density_image -> colorResolve ($i, $i, $i);
    }

    foreach my $gp_ref ($self -> get_group_refs) {
        #my $gp_ref = $self -> get_group_ref (group => $gp_id);
        
        my $RGB = int ((1 - $gp_ref -> get_density_pct) * 255);

        my $colour = $density_image -> colorClosest ($RGB, $RGB, $RGB);
        #print "$colour $RGB";
        $density_image -> setPixel ($self -> convert_coord_map_to_image (coord => scalar $gp_ref -> get_coord_array), $colour);
    }

    $img = $density_image -> png;
    $self -> set_param (DENSITY_IMAGE => $img);
    
    return $img;
}

sub to_image {
    my $self = shift;
    
    my $png = $self -> get_param ('DENSITY_IMAGE');
    
    my $img = GD::Image -> new ($png);

    #  now we add the state colours.
    #  Needs to be here because GD does not retain them in
    #  the cloned image if they are not used
    #  (as is the case with the density image).
    my @colours = (
        'transparent',
        '255,255,0',   #  yellow   #  CHEATING CHEATING - should be of length MAX_STATE
        '255,0,0',     #  red
        '0,255,255',   #  green
    );

    my %state_colours;
    my %state_colours_hsv;
    my $state = 0;
    foreach my $colour (@colours) {
        #print "$i ";
        if ($colour =~ /transparent|-/i) { #  gets transparent and any negative values
            $state_colours{$state} = -1;
        }
        else {
            my @rgb = split (",", $colour);
            $state_colours{$state} = $img -> colorResolve (@rgb);
            $state_colours_hsv{$state} = [$self -> rgb_to_hsv(@rgb)];
        }
        $state ++;
    }


    my %gps_change_this_iter = $self -> get_changed_this_iter;
    
    my @order = qw /3 2 1/;  #  MORE CHEATING
    foreach $state (@order) {
        my $gp_hash = $self -> get_groups_at_state (state => $state);
        delete @gps_change_this_iter{keys %$gp_hash};
        foreach my $gp_id (keys %$gp_hash) {
            my $gp_ref = $self -> get_group_ref (group => $gp_id);
            my ($x, $y) = $self -> convert_coord_map_to_image (coord => scalar $gp_ref -> get_coord_array);
            
            #  now work out the colour.  The intensity depends on the density
            my $density = $gp_ref -> get_density_pct;
            my $v = int ((1 - $density) * 50);
            $v = ($v - $v % 5) / 50 + 0.5;  #  scale between 0.5-1, using every fifth value
            $v = 1;  #  override for now
            my @hsv = @{$state_colours_hsv{$state}};
            my @rgb = $self -> hsv_to_rgb (@{$state_colours_hsv{$state}}[0,1], $v);
            my $colour = $img -> colorResolve (@rgb);
            $img -> setPixel ($x, $y, $colour);
        }
    }
    
    #whatever is left has changed density
    foreach my $gp_id (keys %gps_change_this_iter) {
        my $gp_ref = $self -> get_group_ref (group => $gp_id);
        my $RGB = int ((1 - $gp_ref -> get_density_pct) * 255);
        my $colour = $img -> colorClosest ($RGB, $RGB, $RGB);
        my ($x, $y) = $self -> convert_coord_map_to_image (coord => scalar $gp_ref -> get_coord_array);
        $img -> setPixel ($x, $y, $colour);
    }
    
    #  The timestep text
    my $text_colour = $img -> colorResolve (0, 0, 0);   #  CHEATING
    my ($x, $y) =
      $self -> convert_coord_map_to_image (coord => [-352000, 800000]);  #  CHEATING
    
    my $text = $self -> get_param ('LABEL')
             . q{ }
             . $self -> get_param ('TIMESTEP');
    $img -> string (gdGiantFont, $x, $y, $text, $text_colour);
    
    return $img -> png;
}

sub write_image {
    my $self = shift;
    my %args = @_;
    
    my $timestep = defined $args{timestep} ? $args{timestep} : $self -> get_param ('TIMESTEP');
    
    #  underhanded - need to change usage of outpfx
    my $pfx = basename($self -> get_param ('OUTPFX'));
    my $file_name = $pfx . "_$timestep.png";
    
    $self -> update_log (text => "Writing image file $file_name\n");
    
    open (IMAGEFILE, ">$file_name");
    binmode (IMAGEFILE);
    print IMAGEFILE $args{image};
    close IMAGEFILE;
    
    return $file_name;
}


sub write_model_output_to_csv {
    my $self = shift;
    my %args = @_;
    my $file_name = $args{file};

    print "Writing model output to $file_name\n";
    # NEED OTHER STUFF HERE, or generalise
    my @vars = qw/endtime state source bodycount/;  
   
    my $event_ref = $self -> get_events_ref;

    my $fh;
    my $success = open ($fh, '>', $file_name);
    croak "Unable to open $file_name\n" if ! $success;

    print $fh 'X,Y,starttime,' . join ($comma, @vars) . ",density\n";  
    
    my @line;
    
    my $events = $self->get_group_events_ref;
    my $events_by_time = $events->{BY_TIME};

    BY_TIMESTEP:
    foreach my $time_step (sort numerically keys %$events_by_time) {
        
        my $group_event_hash =
          $self->get_group_events (timestep => $time_step);

        BY_GROUP:
        foreach my $group (sort keys %$group_event_hash) {

            my $group_ref = $self->get_group_ref (group => $group);
            my @coord = $group_ref->get_coord_array;
            my $density = $group_ref->get_density;

            my $events_this_group = $group_event_hash->{$group};
            
            BY_EVENT_TYPE:
            foreach my $event_type (sort keys %$events_this_group) {
                my $event_details = $events_this_group->{$event_type};

#print Data::Dumper::Dumper ($event_details);

                my @line;
                
                BY_HEADER_COL:
                foreach my $key (@vars) {
                    #  avoid undefs and autovivification
                    my $value = exists $event_details->{$key}
                              ? $event_details->{$key}
                              : $null_string;  
                    if (! defined $value) {
                        $value = $null_string;
                    }
                    push @line, $value;
                }
                print $fh join ($comma, @coord, $time_step, @line, $density) . "\n";
            }
        }
    }

    $fh->close || croak "Could not close $file_name\n";

    return;
}

sub convert_coord_map_to_image {
    my $self = shift;
    my %args = @_;
    my $coord = $args{coord} || croak "coord not specified\n";

    my $cell_size = $self -> get_param('IMAGE_CELLSIZE');
    my ($map_x, $map_y) = @$coord;
    my $cell_x = int ($map_x - $self -> get_param ('MIN_X')) / $cell_size;
    my $cell_y = int ($self -> get_param ('MAX_Y') - $map_y) / $cell_size;
    return ($cell_x, $cell_y);
}

sub set_events_ref {
    my $self = shift;
    my %args = @_;
    
    croak "Events not defined\n" if ! defined $args{events};
    croak "Events not a hash ref\n" if (ref $args{events}) !~ /HASH/;
    
    $self->{EVENTS} = $args{events};
}


sub get_events_ref {
    my $self = shift;
    
    $self->{EVENTS} = {} if ! defined $self->{EVENTS};
    
    return $self->{EVENTS};
}

#  we keep separate track of events for all groups or specific groups
sub get_group_events_ref {
    my $self = shift;
    my $events_ref = $self -> get_events_ref;
    $events_ref->{GROUPS} = {} if ! defined $events_ref->{GROUPS};
    return $events_ref->{GROUPS};
}

#  get the set of group events for a timestep
sub get_group_events {
    my $self = shift;
    my %args = @_;
    my $timestep = defined $args{timestep}
                    ? $args{timestep}
                    : $self -> get_param ('TIMESTEP');
    
    my $e_ref = $self -> get_group_events_ref;
    my $events = $e_ref->{BY_TIME}{$timestep} || {};
    return wantarray ? %$events : $events;
}

sub get_global_events_ref {
    my $self = shift;
    my $events_ref = $self -> get_events_ref;
    $events_ref->{GLOBAL} = {} if ! defined $events_ref->{GLOBAL};
    return $events_ref->{GLOBAL};
}

#  get the set of group events for a timestep
sub get_global_events {
    my $self = shift;
    my %args = @_;
    my $timestep = defined $args{timestep}
                    ? $args{timestep}
                    : $self -> get_param ('TIMESTEP');
    
    my $e_ref = $self -> get_global_events_ref;
    my $events = $e_ref->{BY_TIME}{$timestep} || {};
    return wantarray ? %$events : $events;
}

sub schedule_group_events {
    my $self = shift;
    my %args = @_;
    
    my $event_array = $args{event_array} || return 0;  #  silently return if none specified
    
    my $count = 0;
    #  unpack the events and schedule them
    #  just need to add the timestep to the schedule.  It is otherwise the same structure
    foreach my $time_step (keys %$event_array) {
        foreach my $specs (@{$event_array->{$time_step}}) {
            $self -> schedule_group_event (
                timestep => $time_step,
                %$specs,
            );
            $count ++;
        }
    }
    return $count;
}

sub schedule_global_events {
    my $self = shift;
    my %args = @_;
    
    my $event_array = $args{event_array} || return 0;  #  silently return if none specified
    
    my $count = 0;
    #  unpack the events and schedule them
    #  just need to add the timestep to the schedule.  It is otherwise the same structure
    foreach my $time_step (keys %$event_array) {
        foreach my $specs (@{$event_array->{$time_step}}) {
            $self -> schedule_global_event (
                timestep => $time_step,
                %$specs,
            );
            $count ++;
        }
    }
    return $count;
}

sub schedule_group_event {
    my $self = shift;
    my %args = @_;
    
    my $group_id = $args{group} || croak "group not specified\n";
    croak "type not defined\n" if ! defined $args{type};
    my $time_step = defined $args{timestep} ? $args{timestep} : $self -> get_param('TIMESTEP');
    my $type = $args{type} || croak "type not specified\n";
    
    my $events_ref = $self -> get_group_events_ref;
    
    #  get the desired event, create it if necessary
    my $current = $events_ref->{BY_TIME}{$time_step}{$group_id};  
    if ((ref $current) !~ /HASH/) {
        $current = {};
        $events_ref->{BY_TIME}{$time_step}{$group_id} = $current;
    }
    #  a second index structure based on group and then time also refers to $current 
    my $by_g = $events_ref->{BY_GROUP}{$group_id}{$time_step};
    if (! defined $by_g) {
        $events_ref->{BY_GROUP}{$group_id}{$time_step} = $current;
        $by_g = $current;
    }
    #print "$by_g ne $current\n";
    croak "refs not shared between timestep and group\n" if $by_g ne $current;

    #  add the args to the current event
    delete @args{qw /group timestep type/};  #  clean out those used for the structure
    my $this_event = $current->{$type};
    if (defined $this_event) { # if we have a pre-existing event, merge changes onto it
        @$this_event{keys %args} = values %args;
    }
    else {
        $current->{$type} = \%args;
    }

    #my $x = $current;  #  debug point
    return;
}

sub schedule_global_event {
    my $self = shift;
    my %args = @_;
    
    my $time_step = $args{timestep} || $self -> get_param('TIMESTEP');
    delete @args{qw /timestep/};
    
    my $events_ref = $self -> get_global_events_ref;
    
    my $by_time = $events_ref->{BY_TIME}{$time_step};
    if ((ref $by_time) !~ /HASH/) {
        $by_time = {};
        $events_ref->{BY_TIME}{$time_step} = $by_time;
    }
    #  this index is one past latest addition
    #  cannot use number of keys due to cancellations
    my @keys = sort numerically keys %$by_time;
    my $last_key = pop @keys;
    my $this_index = defined $last_key ? $last_key + 1 : 0;  # Start from zero
    
    #  add the remaining keys as events
    $by_time->{$this_index} = {%args};
    
    #  record which indices this type of event occurs
    #  makes cancelling events easier
    my $type = $args{type};
    my $by_type = $events_ref->{BY_TYPE}{$type}{$time_step};
    if ((ref $by_type) !~ /HASH/) {
        $by_type = {};
        $events_ref->{BY_TYPE}{$type}{$time_step} = $by_type;
    }
    if (defined $by_type->{$this_index}) { #  debugging
        print "KKK\n", Data::Dumper::Dumper ($by_time, $by_type);
        croak "double up on schedule\n";
    }
    $by_type->{$this_index} = {%args};
    
    return;
}


#  delete a set of events for a group at a specified timestep
#  defaults to the lot if no events array ref argument specified
sub cancel_group_event {
    my $self = shift;
    my %args = @_;
    my $group = $args{group};
    defined $group || croak "group not specified\n";
    my $time_step = $args{timestep};
    defined $time_step || croak "timestep not specified\n";
    my $type = $args{type};
    croak "type not specified\n" if ! defined $type && ! $args{clear_all};
    
    my $event_ref = $self -> get_group_events_ref;
    my $this_event = $event_ref->{BY_TIME}{$time_step}{$group};
    #my $by_g = $event_ref->{BY_GROUP}{$group}{$time_step};
    
    if (defined $args{clear_all}) { #  delete the lot
        $this_event = undef;
        $event_ref->{BY_TIME}{$time_step}{$group} = undef;
        delete $event_ref->{BY_TIME}{$time_step}{$group};
        $event_ref->{BY_GROUP}{$group}{$time_step} = undef;
        delete $event_ref->{BY_GROUP}{$group}{$time_step};
    }
    else {
        if (exists $this_event->{$type}) {
            $this_event->{$type} = undef;
            delete $this_event->{$type};
        }
        else {
            croak "Cancelling non-existent event $type, $group, $time_step\n";
        }
        
        if (! scalar keys %$this_event) {  #  no more events, clean up
            $this_event = undef;
            $event_ref->{BY_TIME}{$time_step}{$group} = undef;
            delete $event_ref->{BY_TIME}{$time_step}{$group};
            $event_ref->{BY_GROUP}{$group}{$time_step} = undef;
            delete $event_ref->{BY_GROUP}{$group}{$time_step};
        }
    }
}

sub cancel_global_event {
    my $self = shift;
    my %args = @_;
    my $type = $args{type} || croak "type not specified\n";
    my $time_step = $args{timestep};
    defined $time_step || croak "timestep not specified\n";
    my $types = $args{type} || croak "type not specified\n";
    
    my $event_ref = $self -> get_glocal_events_ref;
    my $this_timestep = $event_ref->{BY_TIMESTEP}{$time_step};
    my $this_type_by_t = $event_ref->{BY_TYPE}{$type}{$time_step};
    
    if (defined $args{clear_all}) { #  delete the lot
        $event_ref->{BY_TIME}{$time_step} = undef;
        delete $event_ref->{BY_TIME}{$time_step};
        $this_type_by_t = undef;
        delete $event_ref->{BY_TYPE}{$type}{$time_step};
        delete $event_ref->{BY_TYPE}{$type};
    }
    else {
        my @types;
        if ((ref $types) !~ /ARRAY/) {
            @types = ($types);
        }
        else {
            @types = @$types;
        }
        foreach my $type (@types) {
            #  get the set of events containing this type
            foreach my $index (keys %$this_type_by_t) {
                $this_timestep->{$type} = undef;
                delete $this_timestep->{$type};
            }
        }
        if (! scalar keys %{$$this_type_by_t}) {  #  no more events, clean up
            delete $event_ref->{BY_TIMESTEP}{$time_step};
            #  may need some more deletions
        }
    }
}

sub run_global_events {
    my $self = shift;
    my %args = @_;
    
    my $timestep = defined $args{timestep} ? $args{timestep} : $self -> get_param ('TIMESTEP');
    
    my %global_events = $self -> get_global_events (timestep => $timestep);
    
    #  make sure they happen in sequence 
    my @globals = sort {$global_events{$a} <=> $global_events{$b}} keys %global_events;
    
    my @glob_events = @global_events{@globals};
    
    my $event_count = 0;
    #  do stuff with the global events
    foreach my $event_ref (@glob_events) {
        next if ! defined $event_ref;
        my $type = lc ($event_ref->{type});
        my $fn = "do_event_$type";
        if (! defined $type || ! $self -> can ($fn)) {
            print Data::Dumper::Dumper ($event_ref);
            croak "event type not specified or cannot run this type of event - $fn\n";
        }
        
        $self -> $fn (%$event_ref);
        $event_count ++;
    }
    
    return $event_count;
}

sub run_group_events {
    my $self = shift;
    my %args = @_;
    
    my $timestep = defined $args{timestep} ? $args{timestep} : $self -> get_param ('TIMESTEP');
    
    my %group_events = $self -> get_group_events (timestep => $timestep);
    
    my $event_count = 0;
    foreach my $group (keys %group_events) {
        my $events_ref = $group_events{$group};
        if (! defined $events_ref) {
            warn "Cannot run group events.  Events not defined for $group, $timestep\n";
            next;
        }
        foreach my $type (sort keys %$events_ref) {  #  need a better way of sorting the keys, but alpha will do for now
            $type = lc $type;
            my $fn = "do_event_$type";
            if (! defined $type || ! $self -> can ($fn)) {
                print Data::Dumper::Dumper ($events_ref);
                croak "event type not specified or cannot run this type of event - $fn\n";
            }
            my $event_args = $events_ref->{$type};
            #print "Running $fn $group ". ($event_args->{source} || $null_string) . "\n";
            $self -> $fn (group => $group, %$event_args, run_from => 'run_group_events');
            $event_count ++;
        }
    }
    
    return $event_count;
}

sub numerically {$a <=> $b};

#  need to take care of reference cycles from children - NOT NOW - they are weakened on creation
#sub DESTROY {
#    my $self = shift;
#    print "DESTROYING ", $self -> get_param ('LABEL'), "\n";
##    my %groups = $self -> get_groups_as_hash;
##    foreach my $group_ref (values %groups) {
##        next if ! defined $group_ref;
##        next if ! defined $group_ref -> get_param ('PARENT_POPULATION');
##        print "Cleaning up ", $group_ref -> get_param ('ID') || "", "  ";
##        print "parent pop is ", $group_ref -> get_param ('PARENT_POPULATION') || "", "\n";
##        $group_ref -> set_param (PARENT_POPULATION => undef);  #  free the child's ref to its parent
##    }
##    #  let perl handle the rest
#}

1;



#  NEED TO POD THIS
#  Perl package to run a Susceptible-Infected-Recovered model using a cellular automata framework.
#  Hopefully this will be flexible enough to allow for a great deal of extension and experimentation.
#  Run one species per object for n iterations and then combine them using a higher set of code.
#
#
#  Shawn Laffan
#  School of BEES,
#  University of New South Wales
#  Sydney
#  Australia
#  2052
#  Shawn.Laffan@unsw.edu.au
#
#  The basic model is described in:
#      Doran, R.J. and Laffan, S.W. (in press) Simulating the spatial dynamics of foot and mouth
#          disease outbreaks in feral pigs and livestock in Queensland, Australia, using a
#          Susceptible-Infected-Recovered Cellular Automata model. Preventive Veterinary Medicine.
#
#
#  IMPLEMENTATION:
#  The basic data structure uses hash tables.  It can get messy to read, but is pretty hierarchical.  Indexing using hash tables also speeds up access to the data by reducing unnecessary processing.
#  The system states sub-hash {STATES} is indexed by the model states, each of which contains the set of coordinates satisfying those states.
#  The other system data are stored by coordinate {GROUPS}, and include the states (same data as before, but different structure), densities, the %infected,
#   the deltatron (time since last change), and perhaps some others which have yet to be impolemented like the size of the home range
#  The remainder of the hash elements represent the parameterisations for the object.
#
#  eg:
#  the hash element $object{STATES}{1} contains the list of coordinates with model state 1 (as a third hash table)
#  the hash element $object{GROUPS}{$XY}{STATES} contains the state for coordinate $XY (a duplicate of $object{STATES} for faster searching)
#  the hash element $object{GROUPS}{$XY}{DELTATRON} contains the time since change for coordinate $XY
#  the hash element $object{GROUPS}{$XY}{DENSITY} contains the population density for coordinate $XY
#
#


