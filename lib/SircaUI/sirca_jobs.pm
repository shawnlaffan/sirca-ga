# vim: set ts=4 sw=4 et :

# This package implements the commands sent over
# by the GUI
package SircaUI::sirca_jobs;

use strict;
use warnings;

use Sirca::Landscape;

use Carp;
use Storable qw /nstore retrieve freeze thaw dclone nstore_fd fd_retrieve /;
use Clone qw/clone/;
use Data::Structure::Util qw /unbless/;

use Log::Log4perl qw(get_logger :levels);
my $log = get_logger('Sirca::GUI::Actions');

my $handlers = {
	test_add => \&test_add,
	test_crash => \&test_crash,
    load_from_parameters => \&load_from_parameters,
    load_from_saved_state => \&load_from_saved_state,
    save_state => \&save_state,
    read_parameters => \&read_parameters,
    simulate => \&simulate,
    get_stats => \&get_stats,
    get_parameters => \&get_parameters,
    write_parameters_as_control_file => \&write_parameters_as_control_file,
};


### EXPORTED
sub handle_job {
	my $command = shift;
	my $type = $$command{'type'};
	my $handler = $$handlers{$type};

	if (defined $handler) {
		$log->info("running command $type");
		return &$handler($command);
	} else {
		$log->warn("unknown command $type");
		return handle_unknown_command($command);
	}
}

sub handle_unknown_command {
	my $command = shift;
	my $type = $$command{'type'};
	return { type => 'error', message => "unknown command ($type)" };
}

sub test_add {
	my $command = shift;
	return { type => 'add_result', result => $$command{'a'} + $$command{'b'} };
}

sub test_crash {
    die "CRASHing.. (on purpose.)";
}


# Global landscape used by methods below
my $landscape = undef;

# loads landscape from parameters
sub load_from_parameters {
	my $command = shift;
    $landscape = Sirca::Landscape -> new (config => $$command{'params'});
	return { type => 'finished', finished => 'load_from_parameters' }
}

# loads landscape from Storable data
sub load_from_saved_state {
	my $command = shift;
    if (exists $$command{'saved_state'}) {
        $landscape = thaw ($$command{'saved_state'});
    } elsif (exists $$command{'filename'}) {
        $landscape = retrieve ($$command{'filename'});
    } else {
        return { type => 'error', message => 'invalid parameters (no filename or saved_state)' }
    }

	return { type => 'finished', finished => 'load_from_saved_state' }
}

# saves landscape into a Storable file
sub save_state {
	my $command = shift;
    
    if (not defined $landscape) {
    	return { type => 'error', message => "landscape not loaded" };
    }

    if (exists $$command{'filename'}) {
        nstore $landscape, $$command{'filename'};
    } else {
        return { type => 'error', message => 'invalid parameters (no filename)' }
    }

	return { type => 'finished', finished => 'save_state' }
}

# optionally loads a new landscape, and runs it
sub simulate {
    my $command = shift;

    my $new_params = $$command{'new_params'};
    if (defined $new_params) {
        $landscape = Sirca::Landscape -> new (config => $new_params);
    }

    if (not defined $landscape) {
    	return { type => 'error', message => "landscape not loaded" };
    }

    $landscape -> run();
    return { type => 'finished', finished => 'simulate' }
}

# returns stats ('epicurve') data for a simulated landscape
sub get_stats {
    if (not defined $landscape) {
    	return { type => 'error', message => "landscape not loaded" };
    }

    my $stats_orig = {MODEL_STATS => $$landscape{'MODEL_STATS'} };
    if (not defined $stats_orig) {
    	return { type => 'error', message => "no stats available (has the simulation been run?)" };
    }

    # need to curse the Stats objects since it'll be hard
    # for the GUI to parse the YAML otherwise
    my $stats = clone ($stats_orig);
    unbless ($stats);

    return { type => 'finished', finished => 'get_stats', stats => $stats }
}

# returns a loaded landscape's parameters
sub get_parameters {
    if (not defined $landscape) {
    	return { type => 'error', message => "landscape not loaded" };
    }

    return { type => 'finished', finished => 'get_parameters', 
        params => $$landscape{'PARAMS'} };
}

# loads parameters data (in Perl dict format) into YAML that can be
# read by the GUI
sub read_parameters {
    my $command = shift;
    my $data = $$command{'data'};
    
    open (DATALOG, '>read_parameters.data.log');
    print DATALOG $data;
    close (DATALOG);

    my $VAR1;
    my $params = eval ($data);

    if ($@) {
        my $error = $@;
        $log->error("read_parameters: $error");
    	return { type => 'error', message => "error parsing parameters: $error" };
    } else {
        return { type => 'finished', finished => 'read_parameters', 
            parameters => $params };
    }
}

# writes parameters from the GUI into Perl dict format that can be saved
# into a control file
sub write_parameters_as_control_file {
    my $command = shift;
    my $params = $$command{'params'};

    return { type => 'finished', finished => 'write_parameters_as_control_file',
        control_file_data => Data::Dumper::Dumper($params) };
}

1;

