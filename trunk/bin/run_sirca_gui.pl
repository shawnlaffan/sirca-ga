#!/usr/bin/perl -w
use strict;

#!perl

#  run the sirca model using the Sirca::Landscape package.

use strict;
use warnings;
use Carp;
#use FindBin;
use English qw { -no_match_vars };

use mylib;

#  load up the user defined libs
use Biodiverse::Config qw /use_base/;
BEGIN {
    use_base('SIRCA_LIB');
}

use Sirca::Landscape;

local $| = 1;

my $control_file = shift @ARGV || croak  "Please specify a control file.\n";

my $landscape = Sirca::Landscape -> new (control_file => $control_file);

$landscape -> run;

#  need to make sure the filename is specified by the GUI
#  should also run it as the convention
$landscape -> save_to_storable (filename => 'check.scs');
#$landscape -> save_to_yaml ();

exit;

