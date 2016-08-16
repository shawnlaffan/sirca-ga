#! perl
#  utilities to make life easier for generating sirca models.

#  NOW JUST A STUB THAT POINTS TO Biodiverse::Common

package Sirca::Utilities;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use YAML::Syck;
use Storable qw /dclone store retrieve/;
use Scalar::Util qw /blessed/;

use English qw ( -no_match_vars );
#use Fatal qw ( open );

#  this is most underhanded, as many users will not have access to this
#  it is for the development phase only, though
use base qw /Biodiverse::Common/;

our $VERSION = 0.1;

sub load_params {  # read in the parameters file, set the PARAMS subhash.
    my $self = shift;
    my %args = @_;

    my $file_name = File::Spec->rel2abs($args{file});
    
    my $success = open my $file, '<', $file_name;
    
    croak ("Cannot open $file_name") if ! $success;

    local $/ = undef;
    my $data = <$file>;
    $file->close;

    my $params = eval ($data);
    $self->set_params(%$params);
    #print Data::Dumper::Dumper($params);
    return;
}

#
###  print text to the log.
###  need to add a checker to not dump yaml if not being run by gui
##sub update_log {
##    my $self = shift;
##    my %args = @_;
##    
##    if ($self -> get_param ('RUN_FROM_GUI')) {
##        
##        $args{type} = 'update_log';
##        $self -> dump_to_yaml (data => \%args);
##    }
##    else {
##        print $args{text};
##    }
##    
##}

# FROM http://blog.webkist.com/archives/000052.html
# by Jacob Ehnmark
sub hsv_to_rgb {
    my $self = shift;
    
    my($h, $s, $v) = @_;
    $v = $v >= 1.0 ? 255 : $v * 256;

    # Grey image.
    return((int($v)) x 3) if ($s == 0);

    $h /= 60;
    my $i = int($h);
    my $f = $h - int($i);
    my $p = int($v * (1 - $s));
    my $q = int($v * (1 - $s * $f));
    my $t = int($v * (1 - $s * (1 - $f)));
    $v = int($v);
    
    if($i == 0) { return($v, $t, $p); }
    elsif($i == 1) { return($q, $v, $p); }
    elsif($i == 2) { return($p, $v, $t); }
    elsif($i == 3) { return($p, $q, $v); }
    elsif($i == 4) { return($t, $p, $v); }
    else           { return($v, $p, $q); }
}

sub rgb_to_hsv {
    my $self = shift;
    
    my $var_r = $_[0] / 255;
    my $var_g = $_[1] / 255;
    my $var_b = $_[2] / 255;
    my($var_max, $var_min) = maxmin($var_r, $var_g, $var_b);
    my $del_max = $var_max - $var_min;

    if($del_max) {
        my $del_r = ((($var_max - $var_r) / 6) + ($del_max / 2)) / $del_max;
        my $del_g = ((($var_max - $var_g) / 6) + ($del_max / 2)) / $del_max;
        my $del_b = ((($var_max - $var_b) / 6) + ($del_max / 2)) / $del_max;

        my $h;
        if($var_r == $var_max) { $h = $del_b - $del_g; }
        elsif($var_g == $var_max) { $h = 1/3 + $del_r - $del_b; }
        elsif($var_b == $var_max) { $h = 2/3 + $del_g - $del_r; }

        if($h < 0) { $h += 1 }
        if($h > 1) { $h -= 1 }
    
        return($h * 360, $del_max / $var_max, $var_max);
    }
    else {
        return(0, 0, $var_max);
    }
}

sub maxmin {
    my($min, $max) = @_;
    for (my $i=0; $i<@_; $i++) {
        $max = $_[$i] if($max < $_[$i]);
        $min = $_[$i] if($min > $_[$i]);
    }
    return($max,$min);
}

1;  #  return true

