#package Sirca::Index;
#
##########################
##
##   ADAPTED FROM Biodiverse::Index.   NOW JUST A STUB FOR THAT LIBRARY
#
##  a package to implement an indexing scheme for a Biodiverse::BaseData object.
##  this will normally be stored with each BaseStruct object that needs it, thus allowing multiple
##  indexes for a single BaseData object.
##  currently only indexes numeric fields - text fields are lumped into a single subindex.
#
##  NOTE:  it may be better to implement this using Tree:Simple or similar,
##         but I haven't nutted out how to use it most effectively.
#
##  This approach is not as flexible as it could be.  A pyramid structure may be better.
##
##  Need to add a multiplier to the index so it has at least some prespecified
##    significant digits - use the min and max to assess this
#
#use strict;
#use warnings;
#use Carp;
#
#use Scalar::Util qw /blessed/;
#
#our $VERSION = 0.1;
#
##use List::Util;
#use POSIX qw /fmod ceil/;
#
##use base qw /Sirca::Utilities Biodiverse::BaseData/;  #  CHEATING MOST HEINOUSLY WITH THE BASEDATA USE
##use base qw /Sirca::Utilities/;
#
#use base qw /Biodiverse::Index/;
#
#
##our %PARAMS = (JOIN_CHAR => ":",
##               QUOTES => "'"
##               );
##
##
##sub new {
##    my $class = shift;
##
##    my %args = @_;
##    #my %uc_args;
##    #foreach my $key (keys %args) {  #  upper case them
##    #    $uc_args{uc($key)} = $args{$key};
##    #}
##    
##    my $self = {};
##    bless $self, $class;
##
##    $self -> set_param (%PARAMS);  #  set the defaults
##    
##    #my $parent = $self -> get_param ('PARENT') || confess "parent not specified\n";
##    #$self -> weaken_param ('PARENT');  #  must weaken this
##    
##    $self -> build (@_);
##
##    return $self;
##}
##
##sub build {
##    my $self = shift;
##    my %args = @_;
##    
##    #  what is the index resolution to be?
##    my $resolutions = $args{resolutions} || croak "Index 'resolutions' not specified\n";
##    my @resolutions = @$resolutions;
##    $self -> set_param(RESOLUTIONS=> \@resolutions);
##    
##    #  this should be a ref to a hash with all the element IDs as keys and their coord arrays as values
##    my $element_hash = $args{element_hash} || croak "Argument element_hash not spepcified\n";
##
##    #  are we dealing with blessed objects or just coord array refs?  
##    my @keys = keys %$element_hash;  #  will blow up if not a hash ref
##    my $blessed = blessed $$element_hash{$keys[0]};
##
##    #  get the bounds and the list of unique element columns
##    my (%count, %bounds, %ihash);
##    
##    #  get the coord bounds
##    foreach my $element (@keys) {
##        
##        my $coord_array = $blessed  ? $$element_hash{$element} -> get_coord_array  #  will blow up if no such method
##                                    : $$element_hash{$element}
##                                    ;
##                                    
##        foreach my $i (0 .. $#resolutions) {
##            #print "COLUMNS: $column, $i\n";
##            $ihash{$i}++;
##            $count{$i}{$$coord_array[$i]}++;
##            if (! defined $bounds{max}[$i]) {  #  first use - initiate it (otherwise negative coords cause trouble)
##                $bounds{max}[$i] = $$coord_array[$i];
##                $bounds{min}[$i] = $$coord_array[$i];
##            }
##            else {
##                $bounds{max}[$i] = $$coord_array[$i] if $$coord_array[$i] > $bounds{max}[$i];
##                $bounds{min}[$i] = $$coord_array[$i] if $$coord_array[$i] < $bounds{min}[$i];
##            }
##        }
##        
##        #  and now we allocate this elements to the index hash
##        my $index_key = $self -> snap_to_index (element_array => $coord_array);
##        $$self{ELEMENTS}{$index_key}{$element} = $coord_array;
##    }    
##    
##    #  and finally we calculate the minima and maxima for each index axis
##    #  a value of undef indicates no indexing
##    my (@minima, @maxima);
##    foreach my $i (0 .. $#resolutions) {
##        if ($resolutions[$i] > 0) {
##            push (@minima, $bounds{min}[$i] - fmod ($bounds{min}[$i], $resolutions[$i]));
##            push (@maxima, $bounds{max}[$i] - fmod ($bounds{max}[$i], $resolutions[$i]));
##        } else {
##            push (@minima, undef);
##            push (@maxima, undef);
##        }
##    }
##
##    $self -> set_param(MAXIMA => \@maxima);
##    $self -> set_param(MINIMA => \@minima);
##
##}
##
##
##sub snap_to_index {
##    my $self = shift;
##    my %args = @_;
##    my $element_array = $args{element_array} || croak "element_array not specified\n";
##    (ref ($element_array)) =~ /ARRAY/ || croak "element_array is not an array ref\n";
##
##    #  parameters for the index, not the basestruct object
##    my $sep = $self -> get_param('JOIN_CHAR');
##    my $quotes = $self -> get_param('QUOTES');
##
##    my @columns = @$element_array;
##    my @index_res = @{$self -> get_param('RESOLUTIONS')};
##
##    my @index;
##    foreach my $i (0 .. $#columns) {
##        my $indexValue = 0;
##        if ($index_res[$i] > 0) {
##            $indexValue = $columns[$i] - fmod ($columns[$i], $index_res[$i]);
##            $indexValue += $index_res[$i] if $columns[$i] < 0;
##        }
##        push @index, $indexValue;
##    }
##
##    my $index_key = $self -> list2csv (list => \@index, sep_char => $sep, quote_char => $quotes);
##
##    return wantarray ? (index => $index_key)
##                    : $index_key;
##}
##
##sub delete_from_index {
##    my $self = shift;
##    my %args = @_;
##    
##    my $element = $args{element};
##    
##    my $index_key = $self -> snap_to_index (@_);
##    
##    return if ! exists $$self{$index_key};
##    
##    $$self{ELEMENTS}{$index_key}{$element} = undef;  # free any refs
##    delete $$self{ELEMENTS}{$index_key}{$element};
##    
##    #  clear this index key if it is empty
##    if (keys %{$$self{ELEMENTS}{$index_key}} == 0) {
##        delete $$self{ELEMENTS}{$index_key};
##    }
##    
##}
##
##sub get_index_keys {
##    my $self = shift;
##    return wantarray ? keys %{$$self{ELEMENTS}} : [keys %{$$self{ELEMENTS}}];
##}
##
##
##sub element_exists {
##    my $self = shift;
##    my %args = @_;
##    croak "Argument 'element' missing\n" if ! defined $args{element};
##    return exists $$self{ELEMENTS}{$args{element}};
##}
##
##sub get_index_elements {
##    my $self = shift;
##    my %args = @_;
##    if (! defined $args{element}) {
##        croak "Argument 'element' not defined in call to get_index_elements\n";
##    }
##    if (defined $args{offset}) {  #  we have been given an index element with an offset, so return the elements from the offset
##        my $sep = $self -> get_param('JOIN_CHAR');
##        my $quotes = $self -> get_param('QUOTES');
##        my @elements = ((ref $args{element}) =~ /ARRAY/)  #  is it an array already?
##                        ? @{$args{element}}
##                        : $self -> csv2list (string => $args{element}, sep_char => $sep, quote_char => $quotes)
##                        ;
##        my @offsets = ((ref $args{offset}) =~ /ARRAY/)  #  is it also an array already?
##                        ? @{$args{offset}}
##                        : $self -> csv2list (string => $args{offset}, sep_char => $sep, quote_char => $quotes)
##                        ;
##        for (my $i = 0; $i <= $#elements; $i++) {
##            $elements[$i] += $offsets[$i];
##        }
##        $args{element} = $self -> list2csv(list => \@elements, sep_char => $sep, quote_char => $quotes);
##    }
##    return undef if ! $self -> element_exists (element => $args{element});  #  check after any offset is applied
##    return wantarray ? %{$$self{ELEMENTS}{$args{element}}} : $$self{ELEMENTS}{$args{element}};
##}
##
##sub get_index_elements_as_array {
##    my $self = shift;
##    my $tmpRef = $self -> get_index_elements (@_);
##    return wantarray ? keys %{$tmpRef} : [keys %{$tmpRef}];
##}
##    
##sub predict_offsets {  #  predict the maximum spatial distances needed to search based on the index entries
##    my $self = shift;
##    my %args = @_;
##    if (! $args{spatial_params}) {
##        warn "No conditions specified in predict_distances\n";
##        return undef;
##    }
##    
##    my $progress_bar = $args{progress};
##    
##    #my $parent = $self -> get_param ('PARENT');
##
##    #  derive the full parameter set.  We may not need it, but just in case... (and it doesn't take overly long)
##    #  should add it as an argument
##
##    my $spatial_params = $args{spatial_params};
##    my $conditions = $$spatial_params_hash_ref{conditions};
##    $self -> update_log (text => "[INDEX] PREDICTING SPATIAL INDEX NEIGHBOURS\n$conditions\n");
##    my $index_resolutions = $self -> get_param('RESOLUTIONS');
##    my $minima = $self -> get_param('MINIMA');
##    my $maxima = $self -> get_param('MAXIMA');
##    
##    #  Build all possible neighbour combinations (simpler than trying to evaluate as we go with complex neighbourhoods)
##    my $poss_elements_ref = $self -> get_poss_elements (minima => $minima,
##                                                        maxima => $maxima,
##                                                        resolutions => $index_resolutions
##                                                        );
##    
##    my $sep_char = $self -> get_param ('JOIN_CHAR');
##    my $quote_char = $self -> get_param ('QUOTES');
##    
##    #  generate an array of the index ranges and generate the extrema
##    my @ranges;
##    foreach my $i (0..$#$minima) {
##        $ranges[$i] = $$maxima[$i] - $$minima[$i];
##    }
##    my $extreme_elements_ref = $self -> get_poss_elements (minima => $minima,
##                                                           maxima => $maxima,
##                                                           resolutions => \@ranges
##                                                           );
##    
##    #  now we grab the first order neighbours around each of the extrema
##    #  these will be used to check the index offsets
##    #  (neighbours are needed to ensure we get all possible values)
##    my %element_search_list;
##    my %element_search_arrays;
##    my $total_elements_to_search;
##    foreach my $element (@$extreme_elements_ref) {
##        my $element_array = $self -> csv2list (string => $element,
##                                               sep_char => $sep_char,
##                                               quote_char => $quote_char
##                                               );
##        my $nbrsRef = $self -> get_surrounding_elements (coord => $element_array,
##                                                         resolutions => $index_resolutions,                                                               
##                                                         );
##        $element_search_list{$element} = $nbrsRef;
##        $element_search_arrays{$element} = $element_array;
##        $total_elements_to_search += scalar @$nbrsRef;
##    }
##  
##    #  loop through each permutation of the index resolutions, dropping those
##    #    that cannot fit into our neighbourhood
##    #  this allows us to define an offset distance to search in the up and down directions
##    #    (assuming the index is equal interval)
##    #  start from the minimum to assess the distance upwards we need to search
##    my %validIndexOffsets;
##    my %indexDists;
##    my @refCoord;
##    
##    my $toDo = $total_elements_to_search;
##    my $contains = $self -> get_param ('CONTAINS');
##    my ($count, $printedProgress) = (0, -1);
##        
##    #  this is currently an inefficient search - does not check if the offset has already been done
##    foreach my $extreme_element (keys %element_search_list) {
##        
##        my $extreme_ref = $element_search_arrays{$extreme_element};
##        foreach my $check_element (@{$element_search_list{$extreme_element}}) {
##            my $check_ref = $self -> csv2list(string => $check_element,
##                                             sep_char => $sep_char,
##                                             quote_char => $quote_char);
##
##            #  update progress to GUI
##            $count ++;
##            my $progress = int (100 * $count / $toDo);
##            $progress_bar -> update ("Predicting index offsets\n(index resolution: $contains)\n($count / $toDo)",
##                                     $progress / 100) if $progress_bar;
##
##            COMPARE: foreach my $element (@$poss_elements_ref) {
##                #  evaluate current checkElement against all the others to see if they pass the conditions
##
##                #  get it as an array ref
##                my $element_ref = $self -> csv2list (string => $element,
##                                                     sep_char => $sep_char,
##                                                     quote_char => $quote_char);
##                
##                #  get the correct offset (we are assessing the corners of the one we want)
##                my @list;
##                foreach my $i (0 .. $#$extreme_ref) {
##                    push @list, $$element_ref[$i] - $$extreme_ref[$i];
##                }
##                my $offsets = $self -> list2csv (list => \@list,
##                                                 sep_char => $sep_char,
##                                                 quote_char => $quote_char,
##                                                 );
##                
##                #  skip it if it's already passed
##                next if exists $validIndexOffsets{$offsets};
##                
##                #  might want to also check if it has already been checked and failed?
##                #  Maybe not yet - there may be cases where it fails for one origin, but not for others
##
##                my %dists = $self -> get_distances (element_array1 => $check_ref,
##                                                    element_array2 => $element_ref,
##                                                    params => $spatial_params_hash_ref
##                                                    );
##                my @d = @{$dists{d_list}};
##                my @D = @{$dists{D_list}};
##                my $D = $dists{D};
##                my @c = @{$dists{c_list}};
##                my @C = @{$dists{C_list}};
##                my $C = $dists{C};
##                my @coord = @$element_ref;
##    
##                my $pass = 0;
##                next COMPARE if ! eval ($conditions);
##                
##                $validIndexOffsets{$offsets}++;
##            }  #  :COMPARE
##        }
##    }
##    #print Data::Dumper::Dumper(\%validIndexOffsets);
##    print "Done\n";
##    
##    return wantarray ? %validIndexOffsets : \%validIndexOffsets;
##}
##
##
###sub numerically {$a <=> $b};
##
##1;
##
##
##__END__
##
##=head1 NAME
##
##Biodiverse::Index - Methods to build, access and control an index of elements
##in a Biodiverse::BaseStruct object.  
##
##=head1 SYNOPSIS
##
##  use Biodiverse::Index;
##
##=head1 DESCRIPTION
##
##Store an index to the values contained in the containing object.  This is used
##to reduce the processing time for sppatial operations, as only the relevant
##index elements need be searched for neighbouring elements, as opposed to the
##entire file each iteration.
##The index is ordered using aggregated element keys, so it is a "flat" index.
##The index keys are calculated using numerical aggregation.
##The indexed elements are stored as hash tables within each index element.
##This saves on memory, as perl indexes hash keys globally.
##Storing them as an array would increase the memory burder substantially
##for large files.
##
##
##=head2 Assumptions
##
##Assumes C<Biodiverse::Common> is in the @ISA list.
##
##Almost all methods in the Biodiverse library use {keyword => value} pairs as a policy.
##This means some of the methods may appear to contain unnecessary arguments,
##but it makes everything else more consistent.
##
##List methods return a list in list context, and a reference to that list
##in scalar context.
##
##CHANGES NEEDED
##
##=head1 Methods
##
##These assume you have declared an object called $self of a type that
##inherits these methods, normally:
##
##=over 4
##
##=item  $self = Biodiverse::BaseStruct->new;
##
##=back
##
##
##=over 5
##
##=item $self->build_index ('contains' => 4);
##
##Builds the index.
##
##The C<contains> argument is the average number of base
##elements to be contained in each index key, and controls the resolutions
##of the index axes.  If not specified then the default is 4.
##
##Specifying different values may (or may not) speed up your processing.
##
##=item  $self->delete_index;
##
##Deletes the index.
##
##=item $self->get_index_elements (element => $key, 'offset' => $offset);
##
##Gets the elements contained in the index key $element as a hash.
##
##If C<offset> is specified then it calculates an offset index key and
##returns its contents.  If this does not exist then you will get C<undef>.
##
##=item $self->get_index_elements_as_array (element => $key, 'offset' => $offset);
##
##Gets the elements contained in the index key $element as an array.
##Actually calls C<get_index_elements> and returns the keys.
##
##=item $self->get_index_keys;
##
##Returns an array of the index keys.
##
##=item $self->index_element_exists (element => $element);
##
##Returns 1 if C<element> is specified and exists.  Returns 0 otherwise.
##
##=item $self->snap_to_index (element => $element);
##
##Returns the container index key for an element.
##
##
##=back
##
##=head1 REPORTING ERRORS
##
##I read my email frequently, so use that.  It should be pretty stable, though.
##
##=head1 AUTHOR
##
##Shawn Laffan
##
##Shawn.Laffan@unsw.edu.au
##
##
##=head1 COPYRIGHT
##
##Copyright (c) 2006 Shawn Laffan. All rights reserved.  This
##program is free software; you can redistribute it and/or modify it
##under the same terms as Perl itself.
##
##=head1 REVISION HISTORY
##
##=over 5
##
##=item Version 1
##
##May 2006.  Source libraries developed to the point where they can be
##distributed.
##
##=back
##
##=cut
