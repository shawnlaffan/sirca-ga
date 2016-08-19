#!perl

#  Package for reading, writing and manipulating the outputs from a sirca model run
#  This includes image formats.

package Sirca::Output;

use strict;
use warnings;

use Text::CSV_XS;
use GD;
use GD::Simple;
use Carp;

use Sirca::Utilities;
use base qw/Sirca::Utilities/;

use vars qw {$VERSION %default_params };

$VERSION = 0.1;

%default_params = (
    OUTSUFFIX     => 'fmdout',
    OUTSUFFIX_XML => 'fmdoux',
);

#  not sure why this is here
sub schedule_event {
    my $self = shift;
    my %args = @_;
    #print "HASH TABLE:: " . join (" :: ", %args) . "\n";
    my $coord = $args{coord} || croak "coord not specified\n";
    my $timeStep = $args{timestep} || $self->get_param('TIMESTEP');
    delete $args{coord}; delete $args{timestep};
    
    #my $eventRef = $$self{COORDS}{$coord}{EVENTS};
    my $eventRef = $self->get_events_ref;
    
    #  add the remaining keys as events
    foreach my $key (keys %args) {
        $eventRef->{$timeStep}{$coord}{uc($key)} = $args{$key};
    }
    
}

#  delete a set of events for a coord at a specified timestep
#  defaults to the lot if no events array ref argument specified
sub cancel_event {
    my $self = shift;
    my %args = @_;
    my $coord = $args{coord} || confess "coord not specified\n";
    my $timeStep = $args{timestep} || confess "timestep not specified\n";
    
    my $eventRef = $self->get_events_ref;
    
    if (!defined $args{events}) { #  delete the lot
        $eventRef->{$timeStep}{$coord} = undef;
        delete $eventRef->{$timeStep}{$coord};
    }
    else {
        foreach my $key (@{$args{events}}) {
            delete $eventRef->{$timeStep}{$coord}{uc($key)};
        }
        if (! keys %{$eventRef->{$timeStep}{$coord}}) {  #  empty, delete it
            delete $eventRef->{$timeStep}{$coord};
        }
    }
    
}

sub get_events_ref {
    my $self = shift;
    $self->{EVENTS} //= {};
    return $self->{EVENTS};
}


#  need to move into Sirca::Population
sub write_model_output {
    my $self = shift;
    my $fileName = shift;

    print "Writing model output to $fileName\n";
    my @vars = qw/ENDTIME STATE DENSITY SOURCE/;  # NEED OTHER STUFF HERE
   
    my $eventRef = $self -> get_events_ref;

    open (FILE, '>', $fileName);
    print FILE "X,Y,STARTTIME,". join (",", @vars) . "\n";  
    
    my @line;
    foreach my $timeStep (keys %{$eventRef}) {
        foreach my $coord (keys %{$eventRef->{$timeStep}}) {
            my @line;
            foreach my $key (@vars) {
                my $value = exists $eventRef->{$timeStep}{$coord}{$key}
                          ? $eventRef->{$timeStep}{$coord}{$key}
                          : "";  #  avoids undefs and autovivification
                $value //= "";
                push @line, $value;
            }
            print FILE join (",", $coord, $timeStep, @line) . "\n";
        }
    }

    close FILE || croak "Could not close $fileName\n";

    return;
}


sub txt2csv {
    my $csv = shift;  #  first argument is the csv object
    if ($csv->parse(shift)) {  #  second argument is the string to parse
        my @field = $csv->fields;
        return (@field);
    } else {
        my $err = $csv->error_input;
        print "parse() failed on argument: ", $err, "\n";
    }
}


sub write_model_image {
    #print join (" ", @_);
    my $self = shift;
    my %args = @_;
    
    my $output_image = $args{file} || $self -> get_param ('');
    my $plotTimeStep = shift || 0;
    
    my $img; my $file = $self->get_param('DENSITYIMAGE');
    $img = GD::Image -> new ($file) || die "CANNOT GENERATE IMAGE FROM BASE FILE $file\n";
    #print "IMAGE IS $img\n";

    #  now we add the state colours.
    #  Needs to be here because GD does not retain them in the cloned image if they are not used (as is the case with the density image).
    my @colours = ("transparent","255,255,0","255,0,0","0,255,255");
                   #black, yellow, red, green

    my %stateColours;
    #print "Total colours: " . $img -> colorsTotal . "\n";
    my $state = 0;
    foreach my $colour (@colours) {
        #print "$i ";
        if ($colour =~ /transparent|-/i) { #  gets transparent and any negative values
            $stateColours{$state++} = -1;
            
        } else {
            $stateColours{$state++} = $img -> colorResolve (split (",", $colour));
        }
    }
    #print "Total colours: " . $img -> colorsTotal . "\n";

    my $eventRef = $self->get_events_ref;
    my %times;

    TIMES:  #  need to start from the beginning to find the right states
    foreach my $timeStep (sort numerically keys %{$eventRef}) {  
        #  allow for time steps not starting from 1
        last TIMES if $timeStep > $plotTimeStep;  
    
        COORDS:
        foreach my $coord (keys %{$eventRef->{$timeStep}}) {
        
            if (exists $eventRef->{$timeStep}{$coord}{STATE}) {
                #my $e = $$eventRef{$timeStep}{$coord};
                next COORDS
                  if !defined $eventRef->{$timeStep}{$coord}{ENDTIME};
                #  skip if no state set at the timestep we want
                next COORDS
                  if $eventRef->{$timeStep}{$coord}{ENDTIME} < $plotTimeStep;
                
                $times{$coord}{STARTTIME} = $timeStep;
                $times{$coord}{STATE}     = $eventRef->{$timeStep}{$coord}{STATE};
            }
        }
        #last TIMES if $timeStep == $plotTimeStep;
    }

    foreach my $coord (keys %times) {
        my $state = $times{$coord}{STATE};
        next if $stateColours{$state} eq "-1";
        
        (my $x, my $y) = $self->convert_coord_map_to_image (coord => $coord);
        #print "SETTING PIXEL $x, $y TO $stateColours{$state}, state is $state\n";# if $state == 3;
        #print "$self->{$coord}{EVENTS}{$state}{$event}{STARTTIME} < $timeStep && " .
        #                       "$self->{$coord}{EVENTS}{$state}{$event}{ENDTIME} > $timeStep\n";
        $img->setPixel($x, $y, $stateColours{$state});
    }

    open (my $img_file, '>', $output_image);
    binmode $img_file;
    print $img_file $img->png;
    close $img_file;

}

sub numerically {$a <=> $b};

1;
