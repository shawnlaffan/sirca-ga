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

use Sirca::Landscape;

local $| = 1;

#  make sure we can build using pp
exit (0) if $ENV{BDV_PP_BUILDING};

use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'control_file|c=s',  'The control file containing the configuration parameters', { required => 1 } ],
  [],
  [ 'help',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}


my $control_file = $opt->control_file || croak  "Please specify a control file.\n";

my $landscape = Sirca::Landscape->new (control_file => $control_file);

$landscape->run;

#  need to make sure the filename is specified by the GUI
#  should also run it as the convention
$landscape->save_to_storable (filename => 'check.scs');


exit;

