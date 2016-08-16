#!perl

#  generate a set of epicurves and animated gifs for a Sirca model run

use strict;
use warnings;
use Carp;

use rlib;

use Sirca::Landscape;
use Sirca::Population;
use GD::Image;
use GD;
#use FindBin qw ( $Bin );
use File::Basename;
use File::Spec;

use English qw { -no_match_vars };


local $| = 1;

#  run this from a directory on your machine
#  edit these arguments as needed (they really should be command line args)
#  make sure we can build using pp
exit (0) if $ENV{BDV_PP_BUILDING};

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'filename|f=s',  'The Sirca results file to extract results from', { required => 1 } ],
  [ 'repetitions_to_create|r=s', 'Repetitions to create', {optional => 1, default => undef}],

  [ 'generate_epicurve_files|gef=s',  'Generate epicurve files', {optional => 1, default => 1},
  [ 'generate_epicurve_data_files|gedf=s',  'Generate epicurve data files', {optional => 1, default => 1},
  [ 'generate_spatial|gspatial=s',  'Generate spatial data', {optional => 1, default => 1},
  [ 'generate_animations|ganim=s',  'Generate dispersion animations', {optional => 1, default => 1},
   
  [],
  [ 'help',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}


my $filename = $opt->filename; #  input file, must be an arg

#  clunky
my %generate = (
    generate_epicurve_files
      => $opt->generate_epicurve_files
       ? \&generate_epicurve_files
       : undef,
    generate_epicurve_data_files
      => $opt->generate_epicurve_data_files
       ? \&generate_epicurve_data_files
       : undef,
    generate_spatial
      => $opt->generate_spatial
       ? \&generate_spatial
       : undef,
    generate_animations
      => $opt->generate_animations
       ? \&generate_animations
       : undef,
);

my $reps_to_recreate = $opt->repetitions_to_create // 1;
my %options = (
    repetitions_to_create => [eval "$reps_to_recreate"],   #  which repetitions to animate and create spatial data for?
    delete_image_files    => 1,        #  cleanup as we go
    states_to_track       => [1,2,3],  #  which model states to track?
);


my $landscape = eval {
    Sirca::Landscape->new (file => $filename)
};
croak $EVAL_ERROR if $EVAL_ERROR;

my $master_models = $landscape->get_master_models;

while (my ($subname, $subref) = each %generate) {
    next if not $subref;
    eval $subref->();  #  run the sub
    croak $EVAL_ERROR if $EVAL_ERROR;
}


print "FINISHED\n";

exit 1;


sub generate_spatial {
    my @repetitions = @{$options{repetitions_to_create}};

    REPETITION:
    foreach my $repetition (@repetitions) {
        
        #  rebuild the model, extracting the changes as we go
        #  (inefficient, but OK for the moment...)
        #  drop out if a repetition does not exist
        my @summary = eval {
            $landscape->rerun_one_repetition (
                repetition => $repetition,
            );
        };
        if ($EVAL_ERROR) {
            warn $EVAL_ERROR;
            next REPETITION;
        }

    
        foreach my $model ($landscape->get_current_models) {
            my $pfx = basename($model->get_param ('OUTPFX'));
            my $file = $pfx . ".csv";
            $file = File::Spec->rel2abs($file);

            $model->write_model_output_to_csv (file => $file);
        }
    }

    return;
}

#  dump the data from which the epicurve summary stats are generated
sub generate_epicurve_data_files {
    print "Generating epicurve data files\n";

    my $states_to_track = $options{states_to_track};
    my %total_stats = (
        count   => scalar $landscape->get_model_count_stats_ref,
        density => scalar $landscape->get_model_density_stats_ref,
    );

    my $i = 0;
    foreach my $master (@$master_models) {
        my $name = $master->get_param('LABEL');

        foreach my $stat_type (keys %total_stats) {
            my $stats_array = $total_stats{$stat_type}[$i];

            my %fh_hash;
            for my $state (@$states_to_track) {
                my $file = $name . '_EPICURVE_s' . $state . '_' . $stat_type . '_data.csv';
                print "File $state: $file\n";
                open my $fh, '>', $file or croak "Cannot open $file for writing";
                $fh_hash{$state} = $fh;
                my @header = ('timestep');
                foreach my $rep (1 .. $landscape->get_param('REPETITIONS')) {
                    push @header, "r$rep";
                }
                print {$fh} join q{,}, @header;
                print {$fh} "\n";
            }

            #  count the zeroes
            my @zeroes;

            my $j = 1;
            #shift @$stats_array;  #  remove the first one, as it is null
            foreach my $stats_this_iter (@$stats_array) {
                foreach my $state (@$states_to_track) {
                    my $stats_object = $stats_this_iter->[$state];
                    my @data = $stats_object->get_data;
                    if (! scalar @data) {
                        @data = (0) x $landscape->get_param('REPETITIONS');
                    }
                    my $fh = $fh_hash{$state};
                    print {$fh} join q{,}, $j, @data;
                    print {$fh} "\n";
                    
                    #  count the zeroes - NOT WORKING
                    #my $rep = 1;
                    foreach my $count (@data) {
                        if ($count == 0) {
                            $zeroes[$j]{$state}++;
                        }
                        else {
                            $zeroes[$j]{$state}+=0;
                        }
                        #$rep ++;
                    }
                }
                $j++;
            }
            
            #  print out the zeroes
            my $file = $name . '_ZEROES_' . $stat_type . '.csv';
            print "Zero file: $file\n";
            open my $fh, '>', $file or croak "Cannot open $file for writing";
            my @keys = sort {$a<=>$b} keys %{$zeroes[-1]};
            print {$fh} join q{,}, 'iter', @keys;
            print {$fh} "\n";
            foreach my $iter (1 .. $#zeroes) {
                my $zero_array = $zeroes[$iter];
                print {$fh} join q{,}, $iter, @$zero_array{@keys};
                print {$fh} "\n";
            }
        }
        $i++;
    }

    return;    
}

#  dump summary stats for the epicurves
sub generate_epicurve_files {
    my $i = 0;
    foreach my $master (@$master_models) {
        
        #  now we generate the epicurves
        foreach my $type (qw /count density/) {
            foreach my $state (1..3) { #  CHEATING
                my $stats = $landscape->get_model_stats (
                    type       => $type,
                    model_iter => $i,
                    state      => $state,
                );
                
                my $pfx = basename($master->get_param ('OUTPFX'));
                my $file = $pfx
                         . "_EPICURVE_s$state"
                         . "_$type.csv";
                $file = File::Spec->rel2abs($file);
    
                print "Printing $type epicurve to $file\n";
                open (my $fh, '>', $file) or croak "Could not open $file\n";
                print {$fh} $stats;
                $fh->close;
            }
        }
     
        $i++;
    }
    
    return;
}

sub generate_animations {

    foreach my $master (@$master_models) {
        $master->get_image_params;
        print "Getting base density image\n";
    
        $master->get_density_image;
        $master->set_param (WRITE_IMAGE => 1);
    }

    my @repetitions = @{$options{repetitions_to_create}};

    REPETITION:
    foreach my $repetition (@repetitions) {
        
        #  replay the model, writing the images out as we go 
        #  skip if a repetition does not exist
        my @summary = eval {
            $landscape->rerun_one_repetition (repetition => $repetition);
        };
        if ($EVAL_ERROR) {
            warn $EVAL_ERROR;
            next REPETITION;
        }

    
        foreach my $mdl_summary (@summary) {
            my $file_list = $mdl_summary->{IMAGE_FILES};
            my @files = @$file_list;
            my $first_file = $files[0];
            
            my $file1 = shift @files;
            my $image = GD::Image->new ($file1);
            my $gifdata = $image->gifanimbegin (1, 0);
            $gifdata .= $image->gifanimadd (1, 0, 0, 20, 1);    # first frame
            my $last_image = $image;
    
            if ($options{delete_image_files}) {
                unlink ($file1);
            }
    
            while (my $file = shift @files) {
                print "Adding $file\n";
                # make a frame of right size
                my $frame = GD::Image->new($file);
                $gifdata .= $frame->gifanimadd (1, 0, 0, 20, 1, $last_image);     # add frame
                #$gifdata .= $frame->gifanimadd (1, 0, 0, 20, 1);     # add frame
                $last_image = $frame;
                
                if ($options{delete_image_files}) {
                    unlink ($file);
                }
            }
            $gifdata .= $image->gifanimend;   # finish the animated GIF
            my $f_name = File::Spec->rel2abs ($first_file . 'anim.gif');
            print "Output animation is in $f_name\n";
            open (my $fh, '>', $f_name)
              || croak "Cannot open $f_name for writing\n";
            binmode $fh;
            print {$fh} $gifdata;
            $fh->close;
        }
    }

    return;
}

