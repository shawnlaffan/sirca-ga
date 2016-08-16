#!/usr/bin/perl -w
use strict;

#!perl

#  run the sirca model using the Sirca::Landscape package.

use strict;
use warnings;
use Carp;
#use FindBin;
use English qw { -no_match_vars };

use rlib;

#  load up the user defined libs
use Biodiverse::Config qw /use_base/;
BEGIN {
    use_base('SIRCA_LIB');
}

use Sirca::Landscape;
use File::Path qw(make_path);

local $| = 1;


my $control_file = shift @ARGV || croak  "Please specify a control file.\n";

my $box_size = 1000;

my $x_step = 16000;
my $y_step = 15000;

my $min_x_bnd = -387741;
my $max_x_bnd = $min_x_bnd + $x_step * 5;
my $min_y_bnd =  676083;
my $max_y_bnd = $min_y_bnd + $y_step * 4;


for (my $min_x = $min_x_bnd; $min_x <= $max_x_bnd; $min_x += $x_step) {
    for (my $min_y = $min_y_bnd; $min_y <= $max_y_bnd; $min_y += $y_step) {
        foreach my $interact_function ('interact_distance', 'interact_overlap') {
            my $corner = $min_x . '_' . $min_y;
            my $path = File::Spec->catfile($interact_function, $corner);
            make_path ($path);
            
            my $start_event = {
                type  => 'STATE_CHANGE',  #  first arg is the type, the rest are the args to pass on
                state => 2,
                min_dens => 0,
                max_dens => 1.0,
                min_x => $min_x,
                max_x => $min_x + $box_size,
                min_y => $min_y,
                max_y => $min_y + $box_size,
            };

            my $landscape = Sirca::Landscape -> new (
                control_file => $control_file,
            );

            $landscape->add_global_event (
                event      => $start_event,
                model_iter => 0,
                timestep   => 0,
            );

            #  set the interact function
            foreach my $population ($landscape->get_master_models) {
                $population->set_param(INTERACT_FUNCTION => $interact_function);
            }

            $landscape -> run;

            #  need to make sure the filename is specified by the GUI
            #  should also run it as the convention
            my $filename = File::Spec->catfile($path, 'results.scs');
            $landscape -> save_to_storable (filename => $filename);
        }
    }
}

exit;

