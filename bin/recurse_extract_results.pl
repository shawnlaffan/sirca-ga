#perl

#  find all sirca files under a folder and extract the results.
use strict;
use warnings;
use Carp;

use File::Find;
use File::Basename;
use File::Spec;

our @files;

my @x = find(\&wanted, ".");
print @x;

sub wanted {
    return if $File::Find::name !~ m/\.scs$/;
        
    my $filename = $File::Find::name;
    
    push @files, $filename;
};

use FindBin qw /$Bin/;

#print @files;

my $wd = File::Spec->rel2abs(File::Spec->curdir());

foreach my $file (@files) {
    $file = File::Spec->rel2abs($file);
    print $file, "\n";
    croak "file does not exist" if ! -e $file;
    my ($name, $path, $suffix) = fileparse($file, 'scs');
    chdir $path;
    my $cmd = "perl $Bin/extract_results.pl $file";
    my $status = system $cmd;

    if (! $status) {
        warn "Child process failed\n";
        exit;
    }
    
    chdir $wd;
}

