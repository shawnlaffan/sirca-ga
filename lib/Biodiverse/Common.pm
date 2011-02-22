package Biodiverse::Common;

#  a set of common functions for the Biodiverse library

use strict;
use warnings;

use English ( -no_match_vars );

use Carp;

use Readonly;

use Data::DumpXML qw /dump_xml/;
use Data::Dumper  qw /Dumper/;
use YAML::Syck;
use Text::CSV_XS;
use Scalar::Util qw /weaken isweak blessed looks_like_number/;
use Storable qw /nstore retrieve dclone/;
use File::Spec;
use File::Basename;
use POSIX;  #  make all the POSIX functions available to the spatial parameters
use HTML::QuickTable;
#use XBase;

use Math::Random::MT::Auto;  

use Regexp::Common qw /number/;

require Clone;

our $VERSION = '0.15';

my $EMPTY_STRING = q{};

sub clone {
    my $self = shift;
    my %args = @_;  #  only works with argument 'data' for now

    my $cloneref;

    if ((scalar keys %args) == 0) {
        #$cloneref = dclone($self);
        $cloneref = Clone::clone ($self);
    }
    else {
        #$cloneref = dclone ($args{data});
        $cloneref = Clone::clone ($args{data});
    }

    return $cloneref;
}

sub rename_object {
    my $self = shift;
    my %args = @_;
    
    my $new_name = $args{name};
    my $old_name = $self->get_param ('NAME');
    
    $self -> set_param (NAME => $new_name);
    
    my $type = blessed $self;

    print "Renamed $type '$old_name' to '$new_name'\n";
    
    return;
}

sub get_last_update_time {
    my $self = shift;
    return $self -> get_param ('LAST_UPDATE_TIME');
}

sub set_last_update_time {
    my $self = shift;
    my $time = shift || time;
    $self -> set_param (LAST_UPDATE_TIME => $time);
    
    return;
}

#  generalised handler for file loading
#  works in a sequence, evaling until it gets one that works.  
sub load_file {
    my $self = shift;
    my %args = @_;

    croak "Argument 'file' not defined, cannot load from file\n"
      if ! defined ($args{file});
      
    croak "File $args{file} does not exist or is not readable\n"
      if !-r $args{file};

    my $object;
    #foreach my $type (qw /storable yaml xml/) {
    foreach my $type (qw /storable yaml/) {
        my $func = "load_$type\_file";
        $object = eval {$self -> $func (%args)};
        #croak $EVAL_ERROR if $EVAL_ERROR;
        #warn $@ if $@;
        last if defined $object;
    }

    return $object;
}

sub load_storable_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    croak "argument 'file' not defined\n"  if ! defined ($args{file});

    my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX') || $EMPTY_STRING;

    my $file = File::Spec -> rel2abs ($args{file});
    if (! -e $file) {
        croak "[BASEDATA] File $file does not exist\n";
    }

    if (!$args{ignore_suffix} && ($file !~ /$suffix$/)) {
        croak "[BASEDATA] File $file does not have the correct suffix\n";
    }

    #  attempt reconstruction of code refs -
    #  NOTE THAT THIS IS NOT YET SAFE FROM MALICIOUS DATA
    #local $Storable::Eval = 1;

    #  load data from storable file, ignores rest of the args
    $self = retrieve($file);
    if ($Storable::VERSION < 2.15) {
        foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
            $self -> $fn if $self->can($fn);
        }
    }

    return $self;
}

#  REDUNDANT
sub __load_xml_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    return if ! defined ($args{file});
    my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX_XML');

    return if ! -e $args{file};
    return if ! ($args{file} =~ /$suffix$/);

    #  load data from bdx file, ignores rest of the args
    my $xml = Data::DumpXML::Parser->new;
    my $data = $xml->parsefile($args{file});
    $self = shift (@$data);  #  parsefile returns a list, we want the first (and only) element
    foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
        $self -> $fn if $self->can($fn);
    }
    
    return $self;
}

sub load_yaml_file {
    my $self = shift;  #  gets overwritten if the file passes the tests
    my %args = @_;

    return if ! defined ($args{file});
    my $suffix = $args{suffix} || $self->get_param('OUTSUFFIX_YAML') || $EMPTY_STRING;

    return if ! -e $args{file};
    return if ! ($args{file} =~ /$suffix$/);

    $self = YAML::Syck::LoadFile ($args{file});

    #  yaml does not handle waek refs, so we need to put them back in
    foreach my $fn (qw /weaken_parent_refs weaken_child_basedata_refs weaken_basedata_ref/) {
        $self -> $fn if $self->can($fn);
    }
    return $self;

}

sub weaken_basedata_ref {
    my $self = shift;
    
    my $success;

    #  avoid memory leak probs with circular refs
    if ($self->exists_param ('BASEDATA_REF')) {
        $success = $self -> weaken_param ('BASEDATA_REF');

        warn "[BaseStruct] Unable to weaken basedata ref\n"
          if ! $success;
    }
    
    return $success;
}

sub load_params {  # read in the parameters file, set the PARAMS subhash.
    my $self = shift;
    my %args = @_;

    open (my $fh, $args{file}) || croak ("Cannot open $args{file}\n");
    
    local $/ = undef;
    my $data = <$fh>;
    $fh -> close;
    
    my %params = eval ($data);
    $self -> set_param(%params);
    
    return;
}

sub get_param { 
    my $self = shift;
    my $param = shift;
    if (! exists $self->{PARAMS}{$param}) {
        carp "get_param WARNING: Parameter $param does not exist in $self.\n"
            if $self->{PARAMS}{PARAM_CHANGE_WARN};
        return;
    }
    
    return $self->{PARAMS}{$param};
}

#  sometimes we want a reference to the parameter to allow direct manipulation.
#  this is only really needed if it is a scalar, as lists are handled as refs already
sub get_param_as_ref {
    my $self = shift;
    my $param = shift;

    return if ! $self -> exists_param ($param);

    my $value = $self -> get_param ($param);
    my $test_value = $value;  #  for debug
    if (not ref $value) {
        $value = \$self->{PARAMS}{$param};  #  create a ref if it is not one already
        #  debug checker
        carp "issues in get_param_as_ref $value $test_value\n" if $$value ne $test_value;
    }

    return $value;
}

#  sometimes we only care if it exists, as opposed to its being undefined
sub exists_param {
    my $self = shift;
    my $param = shift || croak "param not specified\n";
    
    my $x = exists $self->{PARAMS}{$param};
    return $x;
}

sub get_params_hash {
    my $self = shift;
    my $params = $self->{PARAMS};
    
    return wantarray ? %$params : $params;
}

sub set_param {
    my $self = shift;
#croak join (" ", @_) if (scalar @_ % 2) == 1;
    my %args = @_;

    while (my ($param, $value) = each %args) {
        $self->{PARAMS}{$param} = $value;
        #$value = $EMPTY_STRING if ! defined $value;  #  just to cope with warnings
        #print "Set ". $self->get_param('NAME') . " param $param to $value, $self\n";
    }
    #%args = ();  #  clears memory leak?  (hoping against hope)

    return scalar keys %args;
}

*set_params = \&set_param;

sub delete_param {  #  just passes everything through to delete_params
    my $self = shift;
    $self -> delete_params(@_);

    return;
}

#  sometimes we have a reference to an object we wish to make weak
sub weaken_param {
    my $self = shift;
    my $count = 0;

    foreach my $param (@_) {
        if (! exists $self->{PARAMS}{$param}) {
            croak "Cannot weaken param $param, it does not exist\n";
        }

        if (not isweak ($self->{PARAMS}{$param})) {
            weaken $self->{PARAMS}{$param};
            #print "[COMMON] Weakened ref to $param, $self->{PARAMS}{$param}\n";
        }
        $count ++;
    }

    return $count;
}

sub delete_params {
    my $self = shift;

    my $count = 0;
    foreach my $param (@_) {  #  should only delete those that exist...
        if (delete $self->{PARAMS}{$param}) {
            $count ++;
            print "Deleted parameter $param from $self\n"
                if $self->get_param('PARAM_CHANGE_WARN');
        }
    }  #  inefficient, as we could use a hash slice to do all in one hit, but allows better feedback

    return $count;
}

#  an internal apocalyptic sub.  use only for destroy methods
sub _delete_params_all {
    my $self = shift;
    my $params = $self->{PARAMS};

    foreach my $param (keys %$params) {
        print "Deleting parameter $param\n";
        delete $params->{$param};
    }
    $params = undef;

    return;
}

sub print_params {
    my $self = shift;
    print Data::Dumper::Dumper ($self->{PARAMS});

    return;
}

#  Load a hash of any user defined default params
our %user_defined_params;
BEGIN {

    #  load user defined indices, but only if the ignore flag is not set
    if (     exists $ENV{BIODIVERSE_DEFAULT_PARAMS}
        && ! $ENV{BIODIVERSE_DEFAULT_PARAMS_IGNORE}) {
        print "[COMMON] Checking and loading user defined globals";
        my $x;
        if (-e $ENV{BIODIVERSE_DEFAULT_PARAMS}) {
            print " from file $ENV{BIODIVERSE_DEFAULT_PARAMS}\n";
            local $/ = undef;
            open (FILE, $ENV{BIODIVERSE_DEFAULT_PARAMS});
            $x = eval (<FILE>);
            close (FILE);
        }
        else {
            print " directly from environment variable\n";
            $x = eval "$ENV{BIODIVERSE_DEFAULT_PARAMS}";
        }
        if ($@) {
            my $msg = "[COMMON] Problems with environment variable "
                    . "BIODIVERSE_DEFAULT_PARAMS "
                    . " - check the filename or syntax\n"
                    . $@
                    . "\n$ENV{BIODIVERSE_DEFAULT_PARAMS}\n";
            croak $msg;
        }
        print "Default parameters are:\n", Data::Dumper::Dumper ($x);

        if ((ref $x) =~ /HASH/) {
            @user_defined_params{keys %$x} = values %$x;
        }
    }
}

#  assign any user defined default params
#  a bit risky as it allows anything to be overridden
sub set_default_params {
    my $self = shift;
    my $package = ref ($self);
    
    return if ! exists $user_defined_params{$package};
    
    #  make a clone to avoid clashes with multiple objects
    #  receiving the same data structures
    my $params = $self->clone (data => $user_defined_params{$package});
    
    $self -> set_params (%$params);  
    
    return;
}

#  print text to the log.
#  need to add a checker to not dump yaml if not being run by gui
#  CLUNK CLUNK CLUNK  - need to use the log4perl system
sub update_log {
    my $self = shift;
    my %args = @_;

    if ($self -> get_param ('RUN_FROM_GUI')) {

        $args{type} = 'update_log';
        $self -> dump_to_yaml (data => \%args);
    }
    else {
        print $args{text};
    }

    return;
}

#  for backwards compatibility
*write = \&save_to;

#  some objects have save methods, some do not
*save =  \&save_to;

sub save_to {
    my $self = shift;
    my %args = @_;
    my $file_name = $args{filename}
                    || $args{OUTPFX}
                    || $self->get_param('NAME')
                    || $self->get_param('OUTPFX');

    croak "Argument 'filename' not specified\n" if ! defined $file_name;

    my @suffixes = ($self -> get_param ('OUTSUFFIX'),
                    #$self -> get_param ('OUTSUFFIX_XML'),
                    $self -> get_param ('OUTSUFFIX_YAML'),
                   );

    my ($null, $null2, $suffix) = fileparse ( $file_name, @suffixes ); 
    if ($suffix eq $EMPTY_STRING || ! defined $suffix) {
        $suffix = $self -> get_param ('OUTSUFFIX');
        $file_name .= '.' . $suffix;
    }

    my $tmp_file_name = $file_name . '.tmp';

    my $result;
    if ($suffix eq $self -> get_param ('OUTSUFFIX')) {
        $result = eval {
            $self -> save_to_storable (filename => $tmp_file_name)
        };
    }
    elsif ($suffix eq $self -> get_param ('OUTSUFFIX_YAML')) {
        $result = eval {
            $self -> save_to_yaml (filename => $tmp_file_name)
        };
    }
    #elsif ($suffix eq $self -> get_param ('OUTSUFFIX_XML')) {
    #    return $self -> save_to_xml (filename => "$filename"); 
    #}
    else {  #  default to storable, adding the suffix
        $file_name .= "." . $self -> get_param ('OUTSUFFIX');
        $result = eval {
            $self -> save_to_storable (filename => $tmp_file_name)
        };
    }
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($result) {
        print "[COMMON] Renaming $tmp_file_name to $file_name\n";
        rename ($tmp_file_name, $file_name);
        return $file_name;
    }

    return;
}

sub save_to_storable {  #  dump the whole object to a Storable file.  Get the prefix from $self{PARAMS}, or some other default
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        $file = File::Spec->rel2abs($file || ($prefix . "." . $self->get_param('OUTSUFFIX')));
    }
    $file = File::Spec -> rel2abs ($file);
    print "[COMMON] WRITING TO FILE $file\n";

    #local $Storable::Deparse = 1;  #  store code refs
    eval { nstore $self, $file };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $file;
}

sub save_to_xml {  #  dump the whole object to an xml file.  Get the prefix from $self{PARAMS}, or some other default
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        $file = File::Spec->rel2abs($args{filename} || ($prefix . ".xml"));
        #$file = File::Spec->rel2abs($args{filename} || ($prefix . "." . $self->get_param('OUTSUFFIX_XML')));
    }
    $file = File::Spec->rel2abs($args{filename});

    print "[COMMON] WRITING TO FILE $file\n";

    open (my $fh, ">$file");
    print $fh dump_xml ($self);
    $fh -> close;

    return $file;
}

sub save_to_yaml {  #  dump the whole object to a yaml file.  Get the prefix from $self{PARAMS}, or some other default
    my $self = shift;
    my %args = @_;

    my $file = $args{filename};
    if (! defined $file) {
        my $prefix = $args{OUTPFX} || $self->get_param('OUTPFX') || $self->get_param('NAME') || caller();
        $file = File::Spec->rel2abs($file || ($prefix . "." . $self->get_param('OUTSUFFIX_YAML')));
    }
    $file = File::Spec->rel2abs($file);
    print "[COMMON] WRITING TO FILE $file\n";

    eval {YAML::Syck::DumpFile ($file, $self)};
    croak $EVAL_ERROR if $EVAL_ERROR;

    return $file;
}

sub dump_to_yaml {  #  dump a data structure to a yaml file.
    my $self = shift;
    my %args = @_;

    my $data = $args{data};

    if (defined $args{filename}) {
        my $file = File::Spec->rel2abs($args{filename});
        print "WRITING TO FILE $file\n";
        YAML::Syck::DumpFile ($file, $data);
    }
    else {
        print YAML::Syck::Dump ($data);
        print "...\n";
    }

    return $args{filename};
}

#  escape any special characters in a file name
#  just a wrapper around URI::Escape::escape_uri
sub escape_filename {
    my $self = shift;
    my %args = @_;
    my $string = $args{string};

    croak "Argument 'string' undefined\n"
      if !defined $string;

    use URI::Escape;
    
    return uri_escape ($string);
}


#  handler for the available set of structures.
#  IS THIS CALLED ANYMORE?
sub write_table {
    my $self = shift;
    my %args = @_;
    defined $args{file} || croak "file argument not specified\n";
    my $data = $args{data} || croak "data argument not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";

    $args{file} = File::Spec->rel2abs ($args{file});

    #  now do stuff depending on what format was chosen, based on the suffix
    my ($prefix, $suffix) = lc ($args{file}) =~ /(.*?)\.(.*?)$/;
    if (! defined $suffix) {
        $suffix = "csv";  #  does not affect the actual file name, as it is not passed onwards
    }

    if ($suffix =~ /csv|txt/i) {
        $self -> write_table_csv (%args);
    }
    #elsif ($suffix =~ /dbf/i) {
    #    $self -> write_table_dbf (%args);
    #}
    elsif ($suffix =~ /htm/i) {
        $self -> write_table_html (%args);
    }
    elsif ($suffix =~ /xml/i) {
        $self -> write_table_xml (%args);
    }
    elsif ($suffix =~ /yml/i) {
        $self -> write_table_yaml (%args);
    }
    #elsif ($suffix =~ /shp/) {
    #    $self -> write_table_shapefile (%args);
    #}
    elsif ($suffix =~ /mrt/i) {
        #  some humourless souls might regard this as unnecessary...
        warn "I pity the fool who thinks Mister T is a file format.\n";
        warn "[COMMON] Not a recognised suffix $suffix, using csv/txt format\n";
        $self -> write_table_csv (%args, data => $data);
    }
    else {
        print "[COMMON] Not a recognised suffix $suffix, using csv/txt format\n";
        $self -> write_table_csv (%args, data => $data);
    }
}

sub write_table_csv {
    my $self = shift;
    my %args = @_;
    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my $sep_char = $args{sep_char}
                    || $self -> get_param ('OUTPUT_SEP_CHAR')
                    || q{,};

    my $quote_char = $args{quote_char}
                    || $self -> get_param ('OUTPUT_QUOTE_CHAR')
                    || q{"};

    if ($quote_char =~ /space/) {
        $quote_char = "\ ";
    }
    elsif ($quote_char =~ /tab/) {
        $quote_char = "\t";
    }

    if ($sep_char =~ /space/) {
        $sep_char = "\ ";
    }
    elsif ($sep_char =~ /tab/) {
        $sep_char = "\t";
    }

    open (my $fh, '>', $file)
        || croak "Could not open $file for writing\n";

    eval {
        foreach my $line_ref (@$data) {
            my $string = $self -> list2csv (  #  should pass csv object
                list        => $line_ref,
                sep_char    => $sep_char,
                quote_char  => $quote_char,
            );
            print {$fh} $string . "\n";
        }
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh -> close) {
        print "[COMMON] Write to file $file successful\n";
    }
    else {
        croak "[COMMON] Unable to close $file\n";
    };

    return;
}

#sub write_table_dbf {
#    my $self = shift;
#    my %args = @_;
#    my $data = $args{data} || croak "data arg not specified\n";
#    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
#    my $file = $args{file} || croak "file arg not specified\n";
#    
#    if (-e $file) {
#        print "[COMMON] $file exists - deleting... ";
#        if (! (unlink ($file))) {
#            print "COULD NOT DELETE FILE - check permissions and file locks\n";
#            return;
#        }
#        print "\n";
#    }
#    
#    my $header = shift (@$data);
#    
#    #  set up the field types
#    my @field_types = ("C", ("F") x $#$header);
#    my @field_lengths = (64, (20) x $#$header);
#    my @field_decimals = (undef, (10) x $#$header);
#    my %flds_to_check;
#    @flds_to_check{1 .. $#$header} = (undef) x $#$header;  #  need to check all bar the first field
#    
#    foreach my $record (@$data) {
#        foreach my $j (keys %flds_to_check) {
#            if (defined $record->[$j] and ! looks_like_number $record->[$j]) {  #  assume it's a character type
#                $field_types[$j] = "C";
#                $field_lengths[$j] = 64;
#                $field_decimals[$j] = undef;
#                delete $flds_to_check{$j};
#            }
#        }
#        last if ! scalar keys %flds_to_check;  #  they're all characters, drop out
#    }
#    
#    my $db = XBase -> create (name => $file,
#                              #version => 4,
#                              field_names => $header,
#                              field_types => \@field_types,
#                              field_lengths => \@field_lengths,  
#                              field_decimals => \@field_decimals,
#                              ) || die XBase->errstr;
#    
#    my $i = 0;
#    foreach my $record (@$data) {
#        $db -> set_record ($i, @$record);
#        $i++;
#    }
#    
#    if ($db -> close) {
#        print "[COMMON] Write to file $file successful\n";
#    }
#    else {
#        carp "[COMMON] Write to file $file failed\n";
#    };
#
#    
#}

sub write_table_xml {  #  dump the table to an xml file.
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    if (-e $file) {
        print "[COMMON] $file exists - deleting... ";
        croak "COULD NOT OVERWRITE $file - check permissions and file locks\n"
            if ! unlink $file;
        print "\n";
    }

    open (my $fh, '>', $file);
    eval {
        print $fh dump_xml($data)
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh -> close) {
        print "[COMMON] Write to file $file successful\n";
    }
    else {
        croak "[COMMON] Unable to close $file\n";
    };

    return;
}

sub write_table_yaml {  #  dump the table to a YAML file.
    my $self = shift;
    my %args = @_;

    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    eval {
        $self -> dump_to_yaml (
            %args,
            filename => $file
        )
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    return;
}

#sub write_table_shapefile {
#    carp "Shapefile export not supported due to bugs in shapelib library.\n";
#    return;
#    
#    my $self = shift;
#    my %args = @_;
#    my $data = $args{data} || croak "data arg not specified\n";
#    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
#    my $file = $args{file} || croak "file arg not specified\n";
#    
#    my $header = shift (@$data);
#    
#    my $shape = Geo::Shapelib -> new ({
#                                       Name => $file,
#                                       Shapetype => POINT,  #  point
#                                       FieldNames => $header,
#                                       FieldTypes => ['String', ('Double') x $#$header]
#                                       }
#                                      );
#    
#    my $i = 0;
#    foreach my $record (@$data) {
#        push @{$shape -> {Shapes}}, { Vertices => [[$record->[1],$record->[2],0,0]],
#                                      #ShapeId => $i,  #  for debug - normally set by code
#                                      #SHPType => POINT,
#                                      };
#        push @{$shape -> {ShapeRecords}}, $record;
#        $i++;
#        last if $i == 5;
#    }
#    $shape -> set_bounds;
#    #$shape -> dump;
#    $shape -> save;
#    $shape -> close;
#    
#}

sub write_table_html {
    my $self = shift;
    my %args = @_;
    my $data = $args{data} || croak "data arg not specified\n";
    (ref $data) =~ /ARRAY/ || croak "data arg must be an array ref\n";
    my $file = $args{file} || croak "file arg not specified\n";

    my $qt = HTML::QuickTable -> new();

    my $table = $qt->render($args{data});

    open my $fh, '>', $file;

    eval {
        print {$fh} $table;
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    if ($fh -> close) {
        print "[COMMON] Write to file $file successful\n"
    }
    else {
        croak "[COMMON] Write to file $file failed, unable to close file\n"
    }

    return;
}

sub list2csv {  #  return a csv string from a list of values
    my $self = shift;
    my %args = (quote_char => "'",
                sep_char => ",",
                @_);

    my $csvLine = $args{csv_object};
    if (not defined $csvLine or (blessed $csvLine) !~ /Text::CSV_XS/) {
        $csvLine = $self -> get_csv_object (@_);
    }

    if ($csvLine->combine(@{$args{list}})) {
        return $csvLine->string;
    }
    else {
        croak "list2csv CSV combine() failed for some reason: "
              . $csvLine->error_input
              . ", line $.\n";
    }

    return;
}

sub csv2list {  #  return a list of values from a csv string
    my $self = shift;
    my %args = @_;

    my $csv_obj = $args{csv_object};
    if (! defined $csv_obj
        || (blessed $csv_obj) !~ /Text::CSV_XS/
        ) {
        $csv_obj = $self -> get_csv_object (@_);
    }
    my $string = $args{string};
    $string = $$string if ref $string;

    my @Fld;
    if ($csv_obj->parse($string)) {
        #print "STRING IS: $string";
        @Fld = $csv_obj->fields;
    }
    else {
        my $error_string = join (
            $EMPTY_STRING,
            "csv2list parse() failed on string $string\n",
            $csv_obj->error_input,
            "\nline $.\nQuote Char is ",
            $csv_obj->quote_char,
            "sep char is ",
            $csv_obj->sep_char,
            "\nSkipping\n",
        );
        croak $error_string;
    }

    return wantarray ? @Fld : \@Fld;
}

#  get a csv object to pass to the csv routines
sub get_csv_object {
    my $self = shift;
    my %args = (
        quote_char      => q{"},  #  set some defaults
        sep_char        => q{,},
        binary          => 1,
        blank_is_undef  => 1,
        @_,
    );

    #  csv_xs v0.41 will not ignore invalid args
    #  - this is most annoying as we will have to update this list every time csv_xs is updated
    my %valid_csv_args = (
        quote_char          => 1,
        escape_char         => 1,
        sep_char            => 1,
        eol                 => 1,
        always_quote        => 0,
        binary              => 0,
        keep_meta_info      => 0,
        allow_loose_quotes  => 0,
        allow_loose_escapes => 0,
        allow_whitespace    => 0,
        blank_is_undef      => 0,
        verbatim            => 0,
        empty_is_undef      => 1,
    );

    if (! defined $args{escape_char}) {
        $args{escape_char} = $args{quote_char};
    }

    foreach my $arg (keys %args) {
        if (! exists $valid_csv_args{$arg}) {
            delete $args{$arg};
        }
    }

    my $csv = Text::CSV_XS -> new({%args});

    croak Text::CSV_XS->error_diag ()
      if ! defined $csv;

    return $csv;
}

#############################################################
##  some stuff to handle coords in degrees 

#  some regexes
Readonly my $RE_REAL => qr /$RE{num}{real}/xms;
Readonly my $RE_INT  => qr /$RE{num}{int} /xms;
Readonly my $RE_HEMI => qr {      #  the hemisphere if given as text
                                \s*
                                [NESWnesw]
                                \s*
                        }xms;

#  a few constants
Readonly my $MAX_VALID_DD  => 360;
Readonly my $MAX_VALID_LAT => 90;
Readonly my $MAX_VALID_LON => 180;

Readonly my $INVALID_CHAR_CONTEXT => 3;

#  how many numbers we can have in a DMS string
Readonly my $MAX_DMS_NUM_COUNT => 3;

#  convert degrees minutes seconds coords into decimal degrees
#  e.g.;
#  S23�32'09.567"  = -23.5359908333333
#  149�23'18.009"E = 149.388335833333
sub dms2dd {
    my $self = shift;
    my %args = @_;
    my $coord = $args{coord} || croak "Argument 'coord' not supplied\n";
    #my $is_lat = $args{is_lat}; #  these are passed onwards
    #my $is_lon = $args{is_lon};

    my $msg_pfx = 'Coord error: ';

    my $first_char_invalid;
    if (not $coord =~ m/ \A [\s0-9NEWSnews+-] /xms) {
        $first_char_invalid = substr $coord, 0, $INVALID_CHAR_CONTEXT;
    }

    croak $msg_pfx . "Invalid string at start of coord: $coord\n"
        if defined $first_char_invalid;

    my @nums = eval {
        $self -> _dms2dd_extract_nums ( coord => $coord );
    };
    croak $EVAL_ERROR if ($EVAL_ERROR);

    my $deg = $nums[0];
    my $min = $nums[1];
    my $sec = $nums[2];

    my $hemi = eval {
        $self -> _dms2dd_extract_hemisphere (
            coord => $coord,
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    my $multiplier = 1;
    if ($hemi =~ / [SsWw-] /xms) {
        $multiplier = -1;
    }

    #  now apply the defaults
    #  $deg is +ve, as hemispheres are handled separately
    $deg = abs ($deg) || 0;
    $min = $min || 0;
    $sec = $sec || 0;

    my $dd = $multiplier
            * ( $deg
                + $min / 60
                + $sec / 3600
              );

    my $valid = eval {
        $self -> _dms2dd_validate_dd_coord (
            %args,
            coord       => $dd,
            hemisphere  => $hemi,
        );
    };
    croak $EVAL_ERROR if $EVAL_ERROR;

    #my $res = join (q{ }, $coord, $dd, $multiplier, $hemi, @nums) . "\n";

    return $dd;
}

#  are the numbers we extracted OK?
#  must find three or fewer of which only the last can be decimal 
sub _dms2dd_extract_nums {
    my $self = shift;
    my %args = @_;

    my $coord = $args{coord};

    my @nums = $coord =~ m/$RE_REAL/gxms;
    my $deg = $nums[0];
    my $min = $nums[1];
    my $sec = $nums[2];

    #  some verification
    my $msg;

    if (! defined $deg) {
        $msg = 'No numeric values in string';
    }
    elsif (scalar @nums > $MAX_DMS_NUM_COUNT) {
        $msg = 'Too many numbers in string';
    }

    if (defined $sec) {
        if ($min !~ / \A $RE_INT \z/xms) {
            $msg = 'Seconds value given, but minutes value is floating point';
        }
        elsif ($sec < 0 || $sec > 60) {
            $msg = 'Seconds value is out of range';
        }
    }
    
    if (defined $min) {
        if ($deg !~ / \A $RE_INT \z/xms) {
            $msg = 'Minutes value given, but degrees value is floating point';
        }
        elsif ($min < 0 || $min > 60) {
            $msg = 'Minutes value is out of range';
        }
    }

    #  the valid degrees values depend on the hemisphere,
    #  so are trapped elsewhere

    my $msg_pfx     = 'DMS coord error: ';
    my $msg_suffix  = qq{: '$coord'\n};

    croak $msg_pfx . $msg . $msg_suffix
        if $msg;

    return wantarray ? @nums : \@nums;
}

sub _dms2dd_validate_dd_coord {
    my $self = shift;
    my %args = @_;

    my $is_lat = $args{is_lat};
    my $is_lon = $args{is_lon};

    my $dd   = $args{coord};
    my $hemi = $args{hemisphere};

    my $msg_pfx = 'Coord error: ';
    my $msg;

    #  if we know the hemisphere then check it is in bounds,
    #  otherwise it must be in the interval [-180,360]
    if ($is_lat || $hemi =~ / [SsNn] /xms) {
        if ($is_lon) {
            $msg = "Longitude specified, but latitude found\n"
        }
        elsif (abs ($dd) > $MAX_VALID_LAT) {
            $msg = "Latitude out of bounds: $dd\n"
        }
    }
    elsif ($is_lon || $hemi =~ / [EeWw] /xms) {
        if ($is_lat) {
            $msg = "Latitude specified, but longitude found\n"
        }
        elsif (abs ($dd) > $MAX_VALID_LON) {
            $msg = "Longitude out of bounds: $dd\n"
        }
    }
    elsif ($dd < -180 || $dd > $MAX_VALID_DD) {
        croak "Coord out of bounds\n";
    }
    croak "$msg_pfx $msg" if $msg;

    return 1;
}

sub _dms2dd_extract_hemisphere {
    my $self = shift;
    my %args = @_;

    my $coord = $args{coord};

    my $hemi;
    #  can start with [NESWnesw-]
    if ($coord =~ m/ \A ( $RE_HEMI | [-] )/xms) {
        $hemi = $1;
    }
    #  cannot end with [-]
    if ($coord =~ m/ ( $RE_HEMI ) \z /xms) {
        my $hemi_end = $1;

        croak "Cannot define hemisphere twice: $coord\n"
            if (defined $hemi && defined $hemi_end);

        $hemi = $hemi_end;
    }
    if (! defined $hemi) {
        $hemi = q{};
    }

    return $hemi;
}

#############################################################
## 

#  convert an array to a hash, where the array values are keys and all the values are the same
#  empty arrays return an empty hash
#  if passed a hash, then it sends it straight back
#  croaks if passed a scalar
sub array_to_hash_keys_old {  #  clunky...
    my $self = shift;
    my %args = @_;
    exists $args{list} || croak "Argument 'list' not specified\n";
    my $list_ref = $args{list};

    if (! defined $list_ref) {
        return wantarray ? () : {};  #  return empty if $list_ref not defined
    }

    #  complain if it is a scalar
    croak "Argument 'list' is not an array ref - it is a scalar\n" if ! ref ($list_ref);

    my $value = $args{value};

    my %hash;
    if ((ref $list_ref) =~ /ARRAY/ && scalar @$list_ref) {  #  ref to array of non-zero length
        #  make a copy of the list so we don't wreck any lists used outside the function
        my @list = @{$list_ref};
        my $rebalance;
        if (scalar @list % 2) {  #  uneven non-zero count, better deal with it
            push @list, $value;  #  add a dud value to the end
            $rebalance = 1;
        }
        %hash = @list;
        shift @list;  #  get rid of the first key
        if ($rebalance) {  #  we don't want the dud value to appear as a key
            pop @list;
        } else {
            push @list, $value;  #  balance 
        }
        %hash = (%hash, @list);
    }
    elsif ((ref $list_ref) =~ /HASH/) {
        %hash = %$list_ref;
    }

    return wantarray ? %hash : \%hash;
}

#  make all the hash keys lowercase
sub lc_hash_keys {
    my $self = shift;
    my %args = @_;
    my $hash = $args{hash} || return {};  #  silently return an empty hash if none specified

    my $hash2 = {};  

    foreach my $key (keys %$hash) {
        $hash2->{lc($key)} = $hash->{$key};
    }

    return wantarray ? %$hash2 : $hash2;
}

sub array_to_hash_keys {
    my $self = shift;
    my %args = @_;
    exists $args{list} || croak "Argument 'list' not specified or undef\n";
    my $list_ref = $args{list};

    if (! defined $list_ref) {
        return wantarray ? () : {};  #  return empty if $list_ref not defined
    }

    #  complain if it is a scalar
    croak "Argument 'list' is not an array ref - it is a scalar\n" if ! ref ($list_ref);

    my $value = $args{value};

    my %hash;
    if ((ref $list_ref) =~ /ARRAY/ && scalar @$list_ref) {  #  ref to array of non-zero length
        @hash{@$list_ref} = ($value) x scalar @$list_ref;
    }
    elsif ((ref $list_ref) =~ /HASH/) {
        %hash = %$list_ref;
    }

    return wantarray ? %hash : \%hash;
}

#  sometimes we want to keep the values
sub array_to_hash_values {
    my $self = shift;
    my %args = @_;

    exists $args{list} || croak "Argument 'list' not specified or undef\n";
    my $list_ref = $args{list};

    if (! defined $list_ref) {
        return wantarray ? () : {};  #  return empty if $list_ref not defined
    }

    #  complain if it is a scalar
    croak "Argument 'list' is not an array ref - it is a scalar\n" if ! ref ($list_ref);
    $list_ref = [values %$list_ref] if (ref $list_ref) =~ /HASH/;

    my $prefix = defined $args{prefix} ? $args{prefix} : "data";

    my %hash;
    my $start = "0" x ($args{num_digits} || length $#$list_ref);  #  make sure it has as many chars as the end val
    my $end = defined $args{num_digits}
                        ? sprintf ("%0$args{num_digits}s", $#$list_ref) #  pad with zeroes
                        : $#$list_ref;
    my @keys;
    for my $suffix ("$start" .. "$end") {  #  a clunky way to build it, but the .. operator won't play with underscores
        push @keys, "$prefix\_$suffix"; 
    }
    if ((ref $list_ref) =~ /ARRAY/ && scalar @$list_ref) {  #  ref to array of non-zero length
        @hash{@keys} = $args{sort_array_lists} ? sort numerically @$list_ref : @$list_ref;  #  sort if needed
    }

    return wantarray ? %hash : \%hash;
}

#  get the intersection of two lists
sub get_list_intersection {
    my $self = shift;
    my %args = @_;

    my @list1 = @{$args{list1}};
    my @list2 = @{$args{list2}};

    my %exists;
    @exists{@list1} = (1) x scalar @list1;
    my @list = grep { $exists{$_} } @list2;

    return wantarray ? @list : \@list;
}

#  move an item to the front of the list, splice it out of its first slot if found
#  should use List::MoreUtils::first_index
#  additional arg add_if_not_found allows it to be added anyway
#  works on a ref, so take care
sub move_to_front_of_list {
    my $self = shift;
    my %args = @_;

    my $list = $args{list} || croak "argument 'list' not defined\n";
    my $item = $args{item};

    if (not defined $item) {
        croak "argument 'item' not defined\n";
    }

    my $i = 0;
    my $found = 0;
    foreach my $iter (@$list) {
        if ($iter eq $item) {
            $found ++;
            last;
        }
        $i ++;
    }
    if ($args{add_if_not_found} || $found) {
        splice @$list, $i, 1;
        unshift @$list, $item;
    }

    return wantarray ? @$list : $list;
}

#  guess the field separator in a line
#  the first separator that returns two or more columns is assumed
sub guess_field_separator {
    my $self = shift;
    my %args = @_;  #  these are passed straight through, except sep_char is overridden
    my $string = $args{string};
    $string = $$string if ref $string;
    #  try a sequence of separators, starting with the default parameter
    my @separators = defined $ENV{BIODIVERSE_FIELD_SEPARATORS}  #  these should be globals set by use_base
                    ? @$ENV{BIODIVERSE_FIELD_SEPARATORS}
                    : (',', "\t", ';', " ");
    my $eol = $self->guess_eol(%args);

    my %sep_count;
    my $i = 0;
    foreach my $sep (@separators) {

        #  skip if does not contain the separator
        #  - no point testing in this case
        next if ! ($string =~ /$sep/);  

        my @flds = $self -> csv2list (
            %args,
            sep_char => $sep,
            eol => $eol,
        );
        $sep_count{$#flds} = $sep if $#flds;  #  need two or more fields to result

        $i++;
    }
    #  now we sort the keys, take the highest and use it as the
    #  index to use from sep_count, thus giving us the most common
    #  sep_char
    my @sorted = reverse sort numerically keys %sep_count;
    my $sep = (scalar @sorted && defined $sep_count{$sorted[0]})
        ? $sep_count{$sorted[0]}
        : $separators[0];  # default to first checked
    my $septext = ($sep =~ /\t/) ? '\t' : $sep;  #  need a better way of handling special chars - ord & chr?
    print "[COMMON] Guessed field separator as '$septext'\n";

    return $sep;
}

sub guess_quote_char {
    my $self = shift;
    my %args = @_;  
    my $string = $args{string};
    $string = $$string if ref $string;
    #  try a sequence of separators, starting with the default parameter
    my @q_types = defined $ENV{BIODIVERSE_QUOTES}
                    ? @$ENV{BIODIVERSE_QUOTES}
                    : qw /" '/;
    my $eol = $self->guess_eol(%args);
    #my @q_types = qw /' "/;
    my %q_count;

    my $i = 0;
    foreach my $q (@q_types) {
        my @cracked = split ($q, $string);
        $q_count{$#cracked} = $q if $#cracked and $#cracked % 2 == 0;
        $i++;
    }
    #  now we sort the keys, take the highest and use it as the
    #  index to use from q_count, thus giving us the most common
    #  quotes character
    my @sorted = reverse sort numerically keys %q_count;
    my $q = (defined $sorted[0]) ? $q_count{$sorted[0]} : $q_types[0];
    print "[COMMON] Guessed quote char as $q\n";
    return $q;

    #  if we get this far then there is a quote issue to deal with
    #print "[COMMON] Could not guess quote char in $string.  Check the object QUOTES parameter and escape char in file\n";
    #return;
}

#  guess the end of line character in a string
#  returns undef if there are none of the usual suspects (\n, \r)
sub guess_eol {
    my $self = shift;
    my %args = @_;

    return if ! defined $args{string};
    my $string = $args{string};
    $string = $$string if ref ($string);

    my $pattern = $args{pattern} || '[\n|\r]*';

    $string =~ /($pattern$)/;

    return $1;
}

sub get_next_line_set {
    my $self = shift;
    my %args = @_;

    my $progress_bar        = $args{progress};
    my $file_handle         = $args{file_handle};
    my $target_line_count   = $args{target_line_count};
    my $file_name           = $args{file_name}    || $EMPTY_STRING;
    my $size_comment        = $args{size_comment} || $EMPTY_STRING;
    my $csv                 = $args{csv_object};

    if ($progress_bar) {
        $progress_bar -> pulsate (
            "Loading next $target_line_count lines \n"
            . "of $file_name into memory\n"
            . $size_comment,
              0.1
        );
    }

    #  now we read the lines
    my @lines;
    while (scalar @lines < $target_line_count) {
        my $line = $csv -> getline ($file_handle);
        if (not $csv -> error_diag) {
            push @lines, $line;
        }
        elsif (not $csv -> eof) {
            print $csv -> error_diag;
            $csv -> SetDiag (0);
        }
        if ($csv -> eof) {
            #$self -> set_param (IMPORT_TOTAL_CHUNK_TEXT => $$chunk_count);
            #pop @lines if not defined $line;  #  undef returned for last line in some cases
            last;
        }
    }

    return wantarray ? @lines : \@lines;
}

#  get the metadata for a subroutine
sub get_args {
    my $self = shift;
    my %args = @_;
    my $sub = $args{sub} || croak "sub not specified in get_args call\n";

    my $metadata_sub = "get_metadata_$sub";
    if (my ($package, $subname) = $sub =~ / ( (?:[^:]+ ::)+ ) (.+) /xms) {
        $metadata_sub = $package . 'get_metadata_' . $subname;
    }

    my $sub_args;
    #  use an eval to trap subs that don't allow the get_args option
    if (blessed $self) {
        if ($self -> can ($metadata_sub)) {
            $sub_args = eval {$self -> $metadata_sub (@_)};
        }
        elsif ($self -> can ($sub)) {  #  allow for old system
            $sub_args = eval {$self -> $sub (get_args => 1, @_)};
        }
    }
    else {  #  called in non-OO manner  - not ideal
        carp "get_args called in non-OO manner - this is deprecated.\n";
        #  cope with any package context
        #if (my ($package, $subname) = $sub =~ / ( (?:[^:]+ ::)+ ) (.+) /xms) {
        #    $metadata_sub = $package . 'get_metadata_' . $subname;
        #}
        #my $fn = "$metadata_sub ( " . join (q{,}, @_) . ' )';
        #$sub_args = eval "$fn";
        $sub_args = eval "$metadata_sub()";  #  ignore args for these for now - all should really be OO calls
        if ($EVAL_ERROR) {  #  try the old method
            #  should add a warning here about using old system once new system is implemented properly
            #$fn = "&$sub (undef, get_args => 1, " . join (q{,}, @_) . ')';
            #$sub_args = eval "$fn";
            $sub_args = eval "$sub (undef, get_args => 1)";
        }
    }
    if ($EVAL_ERROR) {
        croak "$sub does not seem to have get_args metadata\n";
        #print $@;
    }

    if (! defined $sub_args) {
        $sub_args = {} ;
    }

    return wantarray ? %$sub_args : $sub_args;
}

sub get_poss_elements {  #  generate a list of values between two extrema given a resolution
    my $self = shift;
    my %args = @_;
    my $soFar = $args{soFar} || [];  #  reference to an array of values
    my $depth = $args{depth} || 0;
    my $minima = $args{minima};  #  should really be extrema1 and extrema2 not min and max
    my $maxima = $args{maxima};
    my $resolutions = $args{resolutions};
    my $precision = $args{precision} || [("%.10f") x scalar @$minima];
    my $sep_char = $args{sep_char} || $self -> get_param('JOIN_CHAR');

    #  need to add rule to cope with zero resolution

    #  go through each element of @$soFar and append one of the values from this level
    my @thisDepth;

    my $min = min ($minima->[$depth], $maxima->[$depth]);
    my $max = max ($minima->[$depth], $maxima->[$depth]);
    my $res = $resolutions->[$depth];

    #  debug stuff
    #if ($res > 20) {
        #my $val = $min;
        #print $val, "::";
        #$val += $res;
        #print $val, "::", $max, "::(sprintf ($precision->[$depth], $val) + 0) <= $max\::",
        #        (sprintf ($precision->[$depth], $val) + 0) <= $max, "::end\n";
        #print $EMPTY_STRING;
    #}

    #  need to fix the precision for some floating point comparisons
    for (my $value = $min;
         (0 + $self -> set_precision (
                precision => $precision->[$depth],
                value => $value)
          ) <= $max;
         $value += $res) {

        my $val = 0
            + $self -> set_precision (
                precision => $precision->[$depth],
                value     => $value,
            );
        if ($depth > 0) {
            foreach my $element (@$soFar) {
                #print "$element . $sep_char . $value\n";
                push @thisDepth, $element . $sep_char . $val;
            }
        } else {
            push (@thisDepth, $val);
        }
        last if $min == $max;  #  avoid infinite loop
    }

    $soFar = \@thisDepth;

    if ($depth < $#$minima) {
        my $nextDepth = $depth + 1;
        $soFar = $self -> get_poss_elements (%args,
                                             sep_char => $sep_char,
                                             precision => $precision,
                                             depth => $nextDepth,
                                             soFar => $soFar
                                             );
    }

    return $soFar;
}

sub get_surrounding_elements {  #  generate a list of values around a single point at a specified resolution
                              #  calculates the min and max and call getPossIndexValues
    my $self = shift;
    my %args = @_;
    my $coordRef = $args{coord};
    my $resolutions = $args{resolutions};
    my $sep_char = $args{sep_char} || $self -> get_param('JOIN_CHAR') || $self -> get_param('JOIN_CHAR');
    my $distance = $args{distance} || 1; #  number of cells distance to check

    my @minima; my @maxima;
    #  precision snap them to make comparisons easier
    my $precision = $args{precision} || [("%.10f") x scalar @$coordRef];

    foreach my $i (0..$#{$coordRef}) {
        #$minima[$i] = sprintf ($precision->[$i], $coordRef->[$i] - ($resolutions->[$i] * $distance)) + 0;
        #$maxima[$i] = sprintf ($precision->[$i], $coordRef->[$i] + ($resolutions->[$i] * $distance)) + 0;
        
        $minima[$i] = 0
            + $self -> set_precision (
                precision => $precision->[$i],
                value     => $coordRef->[$i] - ($resolutions->[$i] * $distance)
            );
        $maxima[$i] = 0
            + $self -> set_precision (
                precision => $precision->[$i],
                value     => $coordRef->[$i] + ($resolutions->[$i] * $distance)
            );
    }

    return $self->get_poss_elements (
        %args,
        minima      =>\@minima,
        maxima      => \@maxima,
        resolutions =>$resolutions,
        sep_char    => $sep_char,
    );
}

sub get_list_as_flat_hash {
    my $self = shift;
    my %args = @_;

    my $list = $args{list} || croak "[Common] Argument 'list' not specified\n";
    delete $args{list};  #  saves passing it onwards

    my %flat_hash;
    my $ref = ref $list;
    if ($ref =~ /ARRAY/) {
        @flat_hash{@$list} = (1) x scalar @$list;
    }
    elsif ($ref =~ /HASH/) {
        foreach my $elt (keys %{$list}) {
            if (not ref $list->{$elt}) {  #  not a ref, so must be a single level hash list
                $flat_hash{$elt} = $list->{$elt};
            }
            else {  #  drill into this list
                my %local_hash = $self -> get_list_as_flat_hash (%args, list => $list->{$elt});
                @flat_hash{keys %local_hash} = values %local_hash;  #  add to this slice
                $flat_hash{$elt} = $args{default_value} if $args{keep_branches};  #  keep this branch element if needed
            }
        }
    }
    else {  #  must be a scalar
        croak "list arg must be a list, not a scalar\n";
    }

    return wantarray ? %flat_hash : \%flat_hash;
}

#  invert a two level hash by keys
sub get_hash_inverted {
    my $self = shift;
    my %args = @_;

    my $list = $args{list} || croak "list not specified\n";

    my %inv_list;

    foreach my $key1 (keys %$list) {
        foreach my $key2 (keys %{$list->{$key1}}) {
            $inv_list{$key2}{$key1} = $list->{$key1}{$key2};  #  may as well keep the value - it may have meaning
        }
    }
    return wantarray ? %inv_list : \%inv_list;
}

#  a twisted mechanism to get the shared keys between a set of hashes
sub get_shared_hash_keys {
    my $self = shift;
    my %args = @_;

    my $lists = $args{lists};
    croak "lists arg is not an array ref\n" if not (ref $lists) =~ /ARRAY/;

    my %shared = %{shift @$lists};  #  copy the first one
    foreach my $list (@$lists) {
        my %tmp2 = %shared;  #  get a copy
        delete @tmp2{keys %$list};  #  get the set not in common
        delete @shared{keys %tmp2};  #  delete those not in common
    }

    return wantarray ? %shared : \%shared;
}

#  recurse through the ISA trees and extract the packages needed
#  adapted from Devel::SymDump
sub get_isa_tree_flattened {
    my $self = shift;
    my %args = @_;
    my $package = $args{package} || blessed ($self);

    my $depth = $args{depth} || 0;

    $depth++;
    if ($depth > 100){
        warn "Deep recursion in ISA\n";
        return;
    }

    my %results;
    # print "DEBUG: package[$package]depth[$depth]\n";
    #my $isaisa;
    no strict 'refs';
    foreach my $isaisa (@{"$package\::ISA"}) {
        $results{$isaisa} ++;
        my @next_level = $self -> get_isa_tree_flattened (package => $isaisa,
                                                          depth   => $depth
                                                         );

        foreach my $subisa (@next_level) {
            $results{$isaisa} ++;
        }

    }
    return wantarray ? keys %results : [keys %results];
}

#  get a list of available subs (analyses) with a specified prefix
#sub get_analyses {
sub get_subs_with_prefix{
    my $self = shift;
    my %args = @_;

    my $prefix = $args{prefix};
    croak "prefix not defined\n" if not defined $prefix;

    my @tree = ((blessed $self), $self -> get_isa_tree_flattened);

    my $syms = Devel::Symdump->rnew(@tree);
    my %analyses;
    my @analyses_array = sort $syms -> functions;
    foreach my $analysis (@analyses_array) {
        next if $analysis !~ /^.*::$prefix/;
        $analysis =~ s/(.*::)*//;  #  clear the package stuff
        $analyses{$analysis} ++;
    }

    return wantarray ? %analyses : \%analyses;
}

#  initialise the PRNG with an array of values, start from where we left off,
#     or use default if not specified
sub initialise_rand {  
    my $self = shift;
    my %args = @_;
    my $seed  = $args{seed};
    my $state = $self -> get_param ('RAND_LAST_STATE')
                || $args{state};

    warn "[COMMON] Ignoring PRNG seed argument ($seed) because the PRNG state is defined\n"
            if defined $seed and defined $state;

    #  don't already have one, generate a new object using seed and/or state params.
    #  the system will initialise in the order of state and seed, followed by its own methods
    my $rand = Math::Random::MT::Auto->new (
        seed  => $seed,
        state => $state,  #  will use this if it is defined
    );

    if (! defined $self -> get_param ('RAND_INIT_STATE')) {
        $self -> store_rand_state_init (rand_object => $rand);
    }

    return $rand;
}

sub store_rand_state {  #  we cannot store the object itself, as it does not serialise properly using YAML
    my $self = shift;
    my %args = @_;

    croak "rand_object not specified correctly\n" if ! blessed $args{rand_object};

    my $rand = $args{rand_object};
    my @state = $rand -> get_state;  #  make a copy - might reduce mem issues?
    croak "PRNG state not defined\n" if ! scalar @state;

    my $state = \@state;
    $self -> set_param (RAND_LAST_STATE => $state);

    if (defined wantarray) {
        return wantarray ? @state : $state;
    }
}

sub store_rand_state_init {  #  Store the initial rand state (assumes it is called at the right time...)
    my $self = shift;
    my %args = @_;

    croak "rand_object not specified correctly\n" if ! blessed $args{rand_object};

    my $rand = $args{rand_object};
    my @state = $rand -> get_state;

    my $state = \@state;

    $self -> set_param (RAND_INIT_STATE => $state);

    if (defined wantarray) {
        return wantarray ? @state : $state;
    }
}

#  find circular refs in the sub from which this is called,
#  or some level higher
#sub find_circular_refs {
#    my $self = shift;
#    my %args = @_;
#    my $level = $args{level} || 1;
#    my $label = $EMPTY_STRING;
#    $label = $args{label} if defined $args{label};
#    
#    use PadWalker qw /peek_my/;
#    use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs
#    
#    my @caller = caller ($level);
#    my $caller = $caller[3];
#    
#    my $vars = peek_my ($level);
#    my $circular = has_circular_ref ( $vars );
#    if ( $circular ) {
#        warn "$label Circular $caller\n";
#    }
#    #else {  #  run silent unless there is a circular ref
#    #    print "$label NO CIRCULAR REFS FOUND IN $caller\n";
#    #}
#    
#}

sub find_circular_refs {
    my $self = shift;

    if (0) {  #  set to 0 to "turn it off"
        eval q'
                use Devel::Cycle;

                foreach my $ref (@_) {
                    print "testing circularity of $ref\n";
                    find_cycle($ref);
                }
                '
    }
}

#  locales with commas as the radix char can cause grief
#  and silently at that
sub test_locale_numeric {
    my $self = shift;
    
    use warnings FATAL => qw ( numeric );
    
    my $x = 10.5;
    my $y = 10.1;
    my $x1 = sprintf ('%.10f', $x);
    my $y1 = sprintf ('%.10f', $y);
    $y1 = '10,1';
    my $correct_result = $x + $y;
    my $result = $x1 + $y1;
    
    use POSIX qw /locale_h/;
    my $locale = setlocale ('LC_NUMERIC');
    croak "$result != $correct_result, this could be a locale issue. "
            . "Current locale is $locale.\n"
        if $result != $correct_result;
    
    return 1;
}

#  need to handle locale issues in string conversions using sprintf
sub set_precision {
    my $self = shift;
    my %args = @_;
    
    my $num = sprintf ($args{precision}, $args{value});
    $num =~ s{,}{\.};  #  replace any comma with a decimal
    
    return $num;
}

sub compare_lists_by_item {
    my $self = shift;
    my %args = @_;
    my $base_ref = $args{base_list_ref};
    my $comp_ref = $args{comp_list_ref};

    my $results  = $args{results_list_ref};

    COMP_BY_ITEM:
    foreach my $index (keys %$base_ref) {
    #while (my ($index, $op) = each %$comparisons) {
        next COMP_BY_ITEM
            if not defined $base_ref->{$index}
               or not exists  $comp_ref->{$index}
               or not defined $comp_ref->{$index};

        #  compare at 10 decimal place precision
        #  this also allows for serialisation which
        #     rounds the numbers to 15 decimals
        #  should really make the precision an option in the metadata
        my $base = $self -> set_precision (
            precision => '%.10f',
            value     => $base_ref->{$index},
        );
        my $comp = $self -> set_precision (
            precision => '%.10f',
            value     => $comp_ref->{$index},
        );

        #  make sure it gets a value of 0 if false
        my $increment = eval {$base > $comp} || 0;  

        #  for debug, but leave just in case
        #carp "$element, $op\n$comp\n$base  " . ($comp - $base) if $increment;  

        #   C is count passed
        #   Q is quantum, or number of comparisons
        #   P is the percentile rank amongst the valid comparisons,
        #      and has a range of [0,1]
        $results->{"C_$index"} += $increment;    
        $results->{"Q_$index"} ++;               
        $results->{"P_$index"} =   $results->{"C_$index"}
                                 / $results->{"Q_$index"};
        
        #  track the number of ties
        if ($base == $comp) {
            $results->{"T_$index"} ++;
        }
    }
    
    return $results;
}

#  use Devel::Symdump to hunt within a whole package
#sub find_circular_refs_in_package {
#    my $self = shift;
#    my %args = @_;
#    my $package = $args{package} || caller;
#    my $label = $EMPTY_STRING;
#    $label = $args{label} if defined $args{label};
#    
#    use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs
#    use Devel::Symdump;
#    
#   
#    my %refs = (
#                array => {sigil => "@",
#                           data => [Devel::Symdump -> arrays ($package)],
#                          },
#                hash  => {sigil => "%",
#                           data => [Devel::Symdump -> hashes ($package)],
#                          },
#                #scalars => {sigil => '$',
#                #           data => [Devel::Symdump -> hashes],
#                #          },
#                );
#
#    
#    foreach my $type (keys %refs) {
#        my $sigil = $refs{$type}{sigil};
#        my $data = $refs{$type}{data};
#        
#        foreach my $name (@$data) {
#            my $var_text = "\\" . $sigil . $name;
#            my $vars = eval {$var_text};
#            my $circular = has_circular_ref ( $vars );
#            if ( $circular ) {
#                warn "$label Circular $package\n";
#            }
#        }
#    }
#    
#}

#  hunt for circular refs using PadWalker
#sub find_circular_refs_above {
#    my $self = shift;
#    my %args = @_;
#    
#    #  how far up to go?
#    my $top_level = $args{top_level} || 1;
#    
#    use Data::Structure::Util qw /has_circular_ref get_refs/; #  hunting for circular refs
#    use PadWalker qw /peek_my/;
#
#
#    foreach my $level (0 .. $top_level) {
#        my $h = peek_my ($level);
#        foreach my $key (keys %$h) {
#            my $ref = ref ($h->{$key});
#            next if ref ($h->{$key}) =~ /GUI|Glib|Gtk/;
#            my $circular = eval {
#                has_circular_ref ( $h->{$key} )
#            };
#            if ($EVAL_ERROR) {
#                print $EMPTY_STRING;
#            }
#            if ( $circular ) {
#                warn "Circular $key, level $level\n";
#            }
#        }
#    }
#
#    return;
#}

sub numerically {$a <=> $b};

sub min {$_[0] < $_[1] ? $_[0] : $_[1]};
sub max {$_[0] > $_[1] ? $_[0] : $_[1]};

1;  #  return true

__END__

=head1 NAME

Biodiverse::Common - a set of common functions for the Biodiverse library.  MASSIVELY OUT OF DATE

=head1 SYNOPSIS

  use Biodiverse::Common;

=head1 DESCRIPTION

This module provides basic functions used across the Biodiverse libraries.
These should be inherited by higher level objects through their @ISA
list.

=head2 Assumptions

Almost all methods in the Biodiverse library use {keyword => value} pairs as a policy.
This means some of the methods may appear to contain unnecessary arguments,
but it makes everything else more consistent.

List methods return a list in list context, and a reference to that list
in scalar context.

=head1 Methods

These assume you have declared an object called $self of a type that
inherits these methods, for example:

=over 4

=item  $self = Biodiverse::BaseData->new;

=back

or

=over 4

=item  $self = Biodiverse::Matrix->new;

=back

or want to clone an existing object

=over 4

=item $self = $old_object -> clone;

(This uses the Storable::dclone method).

=back

=head2 Parameter stuff

The parameters are used to store necessary metadata about the object,
such as values used in its construction, references to parent objects
and hash tables of other values such as exclusion lists.  All parameters are
set in upper case, and forced into uppercase if needed.
There are no set parameters for each object type, but most include NAME,
OUTPFX and the like.  

=over 5

=item  $self->set_param(PARAMNAME => $param)

Set a parameter.  For example,
"$self-E<gt>set_param(NAME => 'hernando')" will set the parameter NAME to the
value 'hernando'

Overwrites any previous entry without any warnings.

=item $self->load_params (file => $filename);

Set parameters from a file.

=item  $self->get_param($param);

Gets the value of a single parameter $param.  

=item  $self->delete_param(@params);

=item  $self->delete_params(@params);

Delete a list of parameters from the object's PARAMS hash.
They are actually the same thing, as delete_param calls delete_params,
passing on any arguments.

=item  $self->get_params_hash;

Returns the parameters hash.

=back

=head2 File read/write

=over 5

=item  $self->load_file (file => $filename);

Loads an object written using the Storable format.  Must satisfy the OUTSUFFIX parameter
for the object type being loaded.

=item  $self->write  (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

=item  $self->write2 (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

Dump the whole object to an xml file using the Storable package.
Get the filename prefix from argument OUTPFX, the parameter OUTPFX,
the parameter NAME or use BIODIVERSE if none of the others are defined.
The filename extension is taken from parameter OUTSUFFIX.
The embed arguments are used to
remove the references to the parent Biodiverse::BaseData object and
any Biodiverse::Matrix objects so they aren't included.  If these are set to
true then C<write()> calls C<write2()>, passing on all arguments.
C<embed_source_data> must be set for C<embed_basedata> and C<embed_matrix> to
have any effect.

=item  $self->load_xml_file (file => $filename);  DISABLED 

Loads an object written using the Data::DumpXML format.  Must satisfy the OUTSUFFIX parameter
for the object type being loaded.

=item  $self->write_xml  (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

=item  $self->write_xml2 (embed_source_data => 0, embed_matrix => 0,
                     embed_basedata => 0);

Dump the whole object to an xml file using Data::DumpXML.
Get the filename prefix from argument OUTPFX, the parameter OUTPFX,
the parameter NAME or use BIODIVERSE if none of the others are defined.
The filename extension is taken from parameter OUTSUFFIX_XML.
The embed arguments are used to
remove the references to the parent Biodiverse::BaseData object and
any Biodiverse::Matrix objects so they aren't included.  If these are set to
true then C<write_xml()> calls C<write_xml2()>, passing on all arguments.
C<embed_source_data> must be set for C<embed_basedata> and C<embed_matrix> to
have any effect.

=back

=head2 General utilities

=over

=item $self->get_surrounding_elements (coord => \@coord, resolutions => \@resolutions, distance => 1, sep_char => $sep_char);

Generate a list of values around a single coordinate at a specified resolution
out to some resolution C<distance> (default 1).  The values are joined together
using $join_index.
Actually just calculates the minima and maxima and calls
C<$self->getPossIndexValues>.

=item $self->weaken_basedata_ref;

Weakens the reference to a parent BaseData object.  This stops memory
leakage problems due to circular references not being cleared out.
http://www.perl.com/pub/a/2002/08/07/proxyobject.html?page=1

=item $self->csv2list (string => $string, quote_char => "'", sep_char => ",");

convert a CSV string to a list.  Returns an array in list context,
and an array ref in scalar context.  Calls Text::CSV_XS and passes the
arguments onwards.

=item  $self->list2csv (list => \@list, quote_char => "'", sep_char => ",");

Convert a list to a CSV string using text::CSV_XS.  Must be passed a list reference.

=back

=head1 REPORTING ERRORS

http://code.google.com/p/biodiverse/issues/list

=head1 AUTHOR

Shawn Laffan

Shawn.Laffan@unsw.edu.au

=head1 COPYRIGHT

Copyright (c) 2006 Shawn Laffan. All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 REVISION HISTORY

=over


=back

=cut
