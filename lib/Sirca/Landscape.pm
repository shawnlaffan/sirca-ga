package Sirca::Landscape;
#  package to handle a collection ("Landscape") of populations in an overall Sirca model

use strict;
use warnings;
use Carp;
use File::Spec;

use English qw { -no_match_vars };

use Sirca::Population;
#use Sirca::Collected_stats;
use Sirca::Stats;

use base qw /Sirca::Utilities/;

sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless {}, $class;

    $self -> set_params (
        REPETITIONS     => 10,
        ITERATIONS      => 10,
        OUTSUFFIX       => 'scs',
        OUTSUFFIX_YAML  => 'scy',
    );

    # try to load an existing file
    if (defined $args{file}) {
        my $file_loaded = eval {$self -> load_file (@_)};
        return $file_loaded;
    }

    #  we're still here, so create the master models
    if (exists $args{control_file}) {
        $self -> process_control_file (file => $args{control_file});
    }
    elsif (exists $args{config}) {
        $self -> set_params (%{$args{config}});
    }
    else {
        croak "no file or config provided to Landscape!\n";
    }

    $self -> init_models;

    return $self;
}

#  process a control file for several sirca models. Add to the object's params
sub process_control_file {  
    my $self = shift;
    my %args = @_;

    my $file = $args{file} || croak "file not specified\n";
    $file = File::Spec->rel2abs($file);
    
    print "Opening control file $file\n";
    local $/ = undef;
    open my $file_h, '<', $file
      or croak "Cannot open $file\n";
    #my $data = <FILE>;
    #my $VAR1;
    my $text = <$file_h>;
    $file_h -> close;

    my $args = eval $text;
    croak "error reading control file\n"
      if $EVAL_ERROR;

    $self -> set_params (%$args);

    return;
}

sub get_model_control {
    my $self = shift;
    my %args = @_;
    
    my $i = $args{model_iter};
    croak "model_iter is not defined\n" if ! defined $i;

    my $control = $args{control};

    #  handle hash structures gracefully
    my $model_ctls = $self -> get_param ('MODEL_CONTROLS');
    if ((ref $model_ctls) !~ /ARRAY/) {
        croak "model controls must be an array\n";
    }
    
    my $value = undef;
    #  don't autovivify
    if (exists $model_ctls->[$i] and exists $model_ctls->[$i]{$control}) {
        $value = $model_ctls->[$i]{$control};
    }
    
    return $value;
}

sub get_model_params {
    my $self = shift;
    my %args = @_;
    
    my $i = $args{model_iter};
    
    #  handle hash structures gracefully
    my $model_ctls = $self -> get_param ('MODEL_CONTROLS');
    if ((ref $model_ctls) !~ /ARRAY/) {
        croak "model controls must be an array list type\n";
    }

    my $value = undef;
    #  don't autovivify
    if (exists $model_ctls->[$i]) {
        $value = $model_ctls->[$i];
    }

    return $value;
}

#  initialise a set of models set by the control file
sub init_models {
    my $self = shift;

    my $repetitions = $self -> get_param ('REPETITIONS');
    my $iterations  = $self -> get_param ('ITERATIONS');
    
    my $model_density_stats = $self -> get_model_density_stats_ref;
    my $model_count_stats   = $self -> get_model_count_stats_ref;

    my $master_models = $self -> get_master_models;
    
    my $a = $self -> get_param ('MODEL_CONTROLS');  #  this is the array of model controls
    
    foreach my $i (0 .. $#$a) {

        # load model object
        my $model;

        my $control_files = $self->get_model_control(
            model_iter => $i,
            control    => 'PARAMSFILES',
        );

        if (defined $control_files) {
            # get model parameters via control files
            $model = Sirca::Population -> new (
                control_files => $control_files,
                ITERATIONS    => $iterations,
            );
        }
        else {
            # get parameters via the global parameters hash
            my $model_params = $self->get_model_params(model_iter => $i);
            $model_params->{ITERATIONS} = $iterations;
            $model = Sirca::Population -> new (
                params_hash => $model_params,
                ITERATIONS  => $iterations,
            );
        }

        $master_models->[$i] = $model;

        $model -> get_image_params;
        my $img = $model -> get_density_image;

        #  zero iteration is the starting state
        for my $j (0 .. $iterations) {
            foreach my $k (1..3) { #  CHEATING
                my $label = $model -> get_param ('LABEL') . "_s$k" . "_t$j";
                $model_count_stats->[$i][$j][$k]   = Sirca::Stats -> new ($label);
                $model_density_stats->[$i][$j][$k] = Sirca::Stats -> new ($label);
            }
        }
    }
    
    # set up the rand streams using user defined seed
    #  override with a defined state if it exists
    my $seed = $self -> get_param ('RAND_SEED');
    my $state = $self -> get_rand_state_at_end (repetition => 0);
    my $rand = $self -> initialise_rand (
        seed  => $seed,
        state => $state,  #  state overrides seed if defined
    );
    $state = $rand -> get_state;  #  get the full array just in case the seed was a single digit effort
    $self -> store_rand_end_state (
        repetition => 0,
        state      => $state
    );
    
}

sub add_global_event {
    my $self = shift;
    my %args = @_;
    
    my $event = $args{event} or croak "event not specified\n";
    
    my $timestep = $args{timestep};
    croak "timestep not specified\n" if !defined $timestep;
    
    my $iter = $args{model_iter};
    
    my $global_events = $self -> get_model_control (
        control    => 'GLOBAL_EVENTS',
        model_iter => $iter,
    );

    push @{$global_events->{$timestep}}, $event;

    return;
}


sub get_master_models {
    my $self = shift;
    
    my $m = $self->{MASTER_MODELS};

    if (!defined $m) {
        $m = $self->{MASTER_MODELS} = [];
    }
    
    return wantarray ? @$m : $m;
}

sub set_current_models {
    my $self = shift;
    my %args = @_;
    
    $self->{CURRENT_MODELS} = $args{models} || [];
}

sub get_current_models {
    my $self = shift;
    
    my $current = $self->{CURRENT_MODELS};

    if (!defined $current) {
        $current = $self->{CURRENT_MODELS} = [];
    }

    return wantarray ? @$current : $current;
}

sub get_model_count_stats_ref {
    my $self = shift;
    
    my $stats = $self->{MODEL_STATS}{COUNT};
    
    if (!defined $stats) {
        $stats = $self->{MODEL_STATS}{COUNT} = [];
    }
    
    return wantarray ? @$stats : $stats;
}

sub get_model_density_stats_ref {
    my $self = shift;

    my $stats = $self->{MODEL_STATS}{DENSITY};
    
    if (!defined $stats) {
        $stats = $self->{MODEL_STATS}{DENSITY} = [];
    }
    
    return wantarray ? @$stats : $stats;
}

sub get_model_stats_ref {
    my $self = shift;

    my $stats = $self->{MODEL_STATS};

    if (!defined $stats) {
        $stats = $self->{MODEL_STATS} = {};
    }

    return wantarray ? %$stats : $stats;
}

sub get_rand_state_at_end {
    my $self = shift;
    my %args = @_;
    my $repetition = $args{repetition};
    
    return undef if $repetition < 0;
    
    return wantarray ? @{$$self{RAND_LAST_STATES}[$repetition]} : $$self{RAND_LAST_STATES}[$repetition];
}

sub store_rand_end_state {
    my $self = shift;
    my %args = @_;
    my $repetition = $args{repetition};
    my $state = $args{state} || $args{rand_object} -> get_state;
    
    # use a bit of autovivification
    $$self{RAND_LAST_STATES}[$repetition] = $state;
}

#  store the events for the current models
sub store_model_events {
    my $self = shift;
    my %args = @_;
    
    my $current_models = $self -> get_current_models;
    my $repetition = $args{repetition};
    
    my $i = 0;
    foreach my $model (@$current_models) {
        my $events = $model -> get_events_ref;
        $$self{STORED_EVENTS}[$repetition][$i] = $events;
        $i++;
    }
}

#  return a reference to a set of stored model events
sub get_stored_model_events {
    my $self = shift;
    my %args = @_;
    
    my $repetition = $args{repetition};
    my $model_iter = $args{model_iter};
    
    my $stored_events = $self->{STORED_EVENTS};
    
    croak "Repetition $repetition does not exist\n"
      if ! exists $stored_events->[$repetition];

    return $$self{STORED_EVENTS}[$repetition][$model_iter];
}


sub run {
    my $self = shift;
    
    my $master_models = $self -> get_master_models;
    my $max_model_iter = $#$master_models;
    my $model_controls = $self -> get_param ('MODEL_CONTROLS');
    my $model_stats = $self -> get_model_stats_ref;
    
    my $repetitions = $self -> get_param ('REPETITIONS');
    
    foreach my $model_run (1 .. $repetitions ) {  
        my $starttime = time();
    
        $self -> run_one_repetition (repetition => $model_run);
        
        $self -> store_model_events (repetition => $model_run);
        
        my $time_taken = time() - $starttime;
        
        $self -> update_log (text => "MODEL ITERATION $model_run TOOK $time_taken seconds\n");

        $self -> set_current_models;  #  clears them

    }
    
    #$self -> dump_to_yaml (filename => "check_stats_c.yml", data => scalar $self -> get_model_count_stats_ref);
    #$self -> dump_to_yaml (filename => "check_stats_d.yml", data => scalar $self -> get_model_density_stats_ref);
    
}

#  run one repetition on a set of clones
sub run_one_repetition {
    my $self = shift;
    my %args = @_;
    
    my $model_run = $args{repetition};
    
    my $master_models       = $self -> get_master_models;
    my $max_model_iter      = $#$master_models;
    my $model_count_stats   = $self -> get_model_count_stats_ref;
    my $model_density_stats = $self -> get_model_density_stats_ref;
    
    my $iterations = $self -> get_param ('ITERATIONS');
    #my $model_controls = $self -> get_param ('MODEL_CONTROLS');

    #  generate the PRNG object from the end of the previous run
    my $state = $self -> get_rand_state_at_end (repetition => $model_run - 1);
    if ($model_run and ! $state) {
        warn "Missing rand state for repetition (", $model_run - 1, ") - have you tried to run a model out of the sequence?\n";
    }
    my $rand = $self -> initialise_rand (state => $state);  #  state overrides seed if defined
    
    #  clone the master models and then start working on them
    my @models;
    foreach my $i (0 .. $max_model_iter) {
        $self -> update_log (text => "\tCLONING " . $$master_models[$i] -> get_param ('LABEL') . "...");
        my $model = $master_models->[$i] -> clone;
        #print "DONE\n";
        $models[$i] = $model;
        
        $model -> set_param (BUILDING => 1);
        
        #  adjust the output filename
        $model -> append_to_names (string => "_$model_run");
        my $label = $model -> get_param ('LABEL');
        
        $model -> set_param (RAND_OBJECT => $rand);  #  all models draw from the same PRNG stream
        
        #  now we schedule any events
        my $count;
        $count = $model -> schedule_global_events (
            event_array => scalar $self -> get_model_control (
                model_iter => $i,
                control => 'GLOBAL_EVENTS',
            )
        );
        $self -> update_log (text => "$label: Scheduled $count global events\n");
        $count = $model -> schedule_group_events  (
            event_array => scalar $self -> get_model_control (
                model_iter => $i,
                control => 'GROUP_EVENTS',
            )
        );
        $self -> update_log (text => "$label: Scheduled $count group events\n");
    }
    
    $self -> set_current_models (models => \@models);
    
    $self -> update_log (text => "TIMESTEP 0\n");
    
    foreach my $mdl (@models) {
        my $count = $mdl -> run_global_events;  #  run events for the zero timestep
        $self -> update_log (text => $mdl -> get_param ('LABEL') . ": Ran $count global events for timestep 0\n");
        $count = $mdl -> run_group_events;
        $self -> update_log (text => $mdl -> get_param ('LABEL') . ": Ran $count group events for timestep 0\n");
    }
        
    #This is where the model actually happens
    #  sequence is :  1.  interact within a population,
    #                 2.  then between populations,
    #                 3.  then any other events like culling occur
    INFECT:  foreach my $iter (1 .. $iterations) {
        
        # run the models
        foreach my $mdl_iter (0 .. $max_model_iter) {
            my $summary = $models[$mdl_iter] -> run (iterations => 1);
            $self -> update_log (text => sprintf ("\t\ttransmissions %4d, bodycount %6.3f\n",
                                            $$summary{TRANSMISSION_COUNT},
                                            $$summary{BODY_COUNT})
                                    );
            #  we will track the transmissions & bodycount later
        }
        
        #  should really interact the models in random order.  
        foreach my $mdl_iter1 (0 .. $max_model_iter) {
            my $mdl1 = $models[$mdl_iter1];
            
            foreach my $mdl_iter2 (0 .. $max_model_iter) {
                #  don't interact with self - we've done it already
                next if $mdl_iter1 eq $mdl_iter2;
                
                my $mdl2 = $models[$mdl_iter2];
                
                my $interact_count = $self -> interact_models (model1 => $mdl1,
                                                               model2 => $mdl2,
                                                               interact_state => 2
                                                               );

                #  only flag if something happened
                if ($interact_count) {
                    $self -> update_log (text => sprintf "\t\t%s -> %s interactions: %d\n",
                                                    $mdl1 -> get_param('LABEL'),
                                                    $mdl2 -> get_param('LABEL'),
                                                    $interact_count
                                          );
                }
            }
        }

        my %stats_we_care_about = $self -> update_model_stats;

        #  stop processing if all the cells are immune or susceptible,
        #  but we need to pad the stats out with zeroes first
        if (! $stats_we_care_about{CARE_FACTOR}) {   
            my $remaining = $iterations - $iter;
            $self -> dump_to_yaml (text => "No infectious or latent cells left in this model.   Padding stats with zeroes\n");
            foreach my $j ($iter+1 .. $iterations) {
                #print "$j ";
                foreach my $mdl_iter (0 .. $max_model_iter) {
                    foreach my $state (1..3) {  #  CHEATING
                        $$model_count_stats[$mdl_iter][$j][$state]   -> add_data (0);
                        $$model_density_stats[$mdl_iter][$j][$state] -> add_data (0);
                    }
                }
            }
            last INFECT;
        }
    }
    
    #  store the rand states to use in a subsequent model or a rebuild
    $self -> store_rand_end_state ( repetition => $model_run,
                                    state => scalar $rand -> get_state,
                                    );
}

#  rerun a calibrated model
sub rerun_one_repetition {
    my $self = shift;
    my %args = @_;
    
    my $model_run = $args{repetition};
    
    my $master_models = $self -> get_master_models;
    my $max_model_iter = $#$master_models;
    my $model_count_stats = $self -> get_model_count_stats_ref;
    my $model_density_stats = $self -> get_model_density_stats_ref;
    
    my $iterations = defined $args{iterations}
                   ? $args{iterations}
                   : $self -> get_param ('ITERATIONS');
    
        
    #  clone the master models and then start working on them
    my @models;
    foreach my $i (0 .. $max_model_iter) {
        $self -> update_log (
            text => "\tCLONING "
                  . $$master_models[$i] -> get_param ('LABEL')
                  . "...\n",
        );
        my $model = $$master_models[$i] -> clone;
        #print "DONE\n";
        $models[$i] = $model;

        $model -> set_param (BUILDING => 0);
        $model -> set_param (
            RUN_FROM_GUI => $self -> get_param ('RUN_FROM_GUI')
                            || undef
        );

        #  adjust the output filename
        $model -> append_to_names (string => "_$model_run");
        my $label = $model -> get_param ('LABEL');

        #  need to add the events we stored before
        my $events = $self -> get_stored_model_events (
            repetition => $model_run,
            model_iter => $i,
        );
        $model -> set_events_ref (events => $events);
    }
    
    $self -> set_current_models (models => \@models);
    
    my @summary;
    my $i = 0;
    foreach my $mdl (@models) {
        my %sub_summary = $mdl -> rerun (%args);
        print $mdl -> get_param ('LABEL'),
              ": Ran $sub_summary{EVENT_COUNT} group events up to timestep $iterations\n";
        $summary[$i] = \%sub_summary;
        $i ++;
    }

    return wantarray ? @summary : \@summary;
}




#  interact two models
sub interact_models {
    my $self = shift;
    my %args = @_;
    my $model1 = $args{model1} || croak "model2 not specified\n";
    my $model2 = $args{model2} || croak "model2 not specified\n";
    my $states = $self -> get_param ('PROP_STATES');

    my ($newState, $interactCount);
    my $default_state1 = $model1 -> get_param('DEFAULTSTATE');
    my $default_state2 = $model2 -> get_param('DEFAULTSTATE');
    my $states1 = $model1 -> get_param ('PROP_STATES');
    my $states2 = $model2 -> get_param ('PROP_STATES');
    
    my $rand = $model1 -> get_param ('RAND_OBJECT');
    
    my $bandwidth = $model1 -> get_param('BANDWIDTH');
    
    my $transmission_count = 0;

    foreach my $mdl1_gp (keys %{$model1 -> get_groups_at_state (state => $$states1{propstate})}) {
        #  snap the first model coord onto the second to determine what to interact with
        #  does not cache the neighbours to reduce other interactions
        
        #  get the neighbours from model2
        my $infectious_gp_ref = $model1 -> get_group_ref (group => $mdl1_gp);
        #my $mdl1_coords = $infectious_gp_ref -> get_coord_array;
        my %nbrs = $model2 -> get_neighbouring_groups ( group_ref => $infectious_gp_ref,
                                                        label => $model1 -> get_param ('LABEL'),
                                                        );
        
        #  THE FOLLOWING IS MODIFIED FROM Population.pm - SHOULD PUT IN A UTILITY SUB
        my @nearest = sort { $nbrs{$a} <=> $nbrs{$b} } keys %nbrs;
        my $max_nbr_count_range =   $infectious_gp_ref -> get_param ('MAX_NBR_COUNT') ||
                                    $model1 -> get_param ('MAX_NBR_COUNT');
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
        
        
        #  need to allow user to vary this per population
        my $max_interact_count = $infectious_gp_ref -> get_param('MAX_INTERACT_COUNT') || 
                                 $model1 -> get_param('MAX_INTERACT_COUNT');
        
        my @range = (ref $max_interact_count) =~ /ARRAY/
                    ? @$max_interact_count
                    : ($max_interact_count, $max_interact_count);
        my $min = shift (@range);
        my $range = (pop @range) - $min;
        my $target_interact_count = int ($min + $rand -> rand ($range));
        
        my $mdl1_label = $model1 -> get_param ('LABEL');
        
        my $interactions = 0;
        BY_NBR: foreach my $neighbour (@$nbr_rand_list_ref) {
            next if (! $model2 -> group_exists (group => $neighbour));  #  skip it if it does not exist
            my $nbr_gp_ref = $model2 -> get_group_ref (group => $neighbour);
            next if $nbr_gp_ref -> get_density == 0;  #  skip it if it is dead
            
            $interactions ++;
            
            # already changed this iteration (eg from cured to susceptible), so skip it
            next if $model2 -> changed_this_iter (group => $neighbour);
            
            my $state = $nbr_gp_ref -> get_state;
            $state = $model2 -> get_param ('DEFAULT_STATE') if ! defined $state;
            
            #  skip non-susceptibles. In future versions we might increase the
            #  latency fraction instead of skipping
            next if $state != $$states2{suscstate};  
            
            my $distance_apart = $nbrs{$neighbour};
            
            #print "VALUES:  $distance_apart , $bandwidth\n";
            
            #  product of densities (as %) weighted by kernel (inverse of distance adjusted by bandwidth)
            my $jointProb =
                            $infectious_gp_ref -> get_density_pct *
                            $nbr_gp_ref -> get_density_pct *
                           ($bandwidth / $distance_apart);

            if ($rand -> rand < $jointProb) {
                $model2 -> update_group_state (group => $neighbour,
                                               state => $$states2{latentstate},
                                               source => $mdl1_label);
                $transmission_count ++;
            }
            last BY_NBR if $interactions >= $target_interact_count;
        }
    }
    ##  need to fix up the interaction tracking
    return $transmission_count;
}


sub update_model_stats {
    my $self = shift;
    my %args = @_;
    
    my $model_count_stats   = $self -> get_model_count_stats_ref;
    my $model_density_stats = $self -> get_model_density_stats_ref;
    
    my @models = $self -> get_current_models;
    
    #  should add a parameter to specify which states we care about
    my @collate_groups_in_states = (1,2,3);  #  CHEATING
    my @collate_dens_in_states   = (1,2,3);
    my %care_about = (  #  used for stopping criteria
        1 => 1,  
        2 => 1
    );

    #  save a few duplicate calcs by caching these values
    #my @dens_sum;
    #my @group_sum;
    my $group_sum_all;
    my $density_sum_all;
    my $care_factor;  #  perhaps not the best name...
    foreach my $mdl_iter (0 .. $#models) {
        my $time_step = $models[$mdl_iter] -> get_param ('TIMESTEP');

        foreach my $state (@collate_dens_in_states) {
            my $dens = $models[$mdl_iter] -> sum_densities_at_state (state => $state);
            my $stats = $model_density_stats->[$mdl_iter][$time_step][$state];
            $stats -> add_data ($dens);
            $density_sum_all += $dens;
        }

        foreach my $state (@collate_groups_in_states) {
            my $count = $models[$mdl_iter] -> sum_groups_at_state (state => $state);
            my $stats = $model_count_stats->[$mdl_iter][$time_step][$state];
            $stats -> add_data ($count);
            $group_sum_all += $count;
            if ($care_about{$state}) {
                $care_factor += $count;
            }
        }
    }

    my %collated = (
        GROUP_SUM   => $group_sum_all,
        DENS_SUM    => $density_sum_all,
        CARE_FACTOR => $care_factor,
    );

    return wantarray ? %collated : \%collated;
}

sub get_model_stats {
    my $self = shift;
    my %args = @_;

    my $iterations = $self -> get_param ('ITERATIONS');
    
    my $model_iter = $args{model_iter};
    my $state = $args{state};
    
    my $type = $args{type} || 'density';
    my $fn = 'get_model_' . $type . '_stats_ref';
    my $stats_ref = $self -> $fn;
    
    my $stats = $stats_ref->[$model_iter];
    
    my $stats_obj = $stats->[0][$state];
    my $text = $stats_obj -> get_stats_header;
    
    foreach my $timestep (0 .. $iterations) {
        $stats_obj = $stats->[$timestep][$state];
        $text .= $stats_obj -> get_stats (
            model     => $model_iter,
            time_step => $timestep,
            type      => $type,
            name      => $timestep
        );
    }
    
    return $text;
}


1;
