#!/usr/bin/perl -w
use strict;
use warnings;


#  process the results of the GISVET analyses

use File::Find;
use File::Basename qw /fileparse/;

my $script = 'extract_results.pl';
my $dir = $0;

our @files;

sub wanted {
        my $filename = $File::Find::name;
        
        return if $filename !~ m/\.scs$/;
        
        push @files, $filename;
    };


find(\&wanted, ".");

print @files;

foreach my $path (@files) {
    my ($filename, $directory, $suffix) = fileparse($path);

    chdir $directory;
    
}