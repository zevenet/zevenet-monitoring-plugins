#!/usr/bin/perl
###############################################################################
#
#    ZEVENET Software License
#    This file is part of the ZEVENET Load Balancer software package.
#
#    Copyright (C) 2014-today ZEVENET SL, Sevilla (Spain)
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

# Check status, established connections and pending connections of backend server in a ZEVENET Load Balancer.
# ZEVENET API V4.0 (https://www.zevenet.com/zapidocv4.0/) is used to retrieve the metrics from ZEVENET Load Balancer.
# Provides performance data.

# Prologue
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use Monitoring::Plugin;
use Fcntl qw(:flock);

use vars qw($VERSION $PROGNAME $verbose $warn $critical $timeout $result);
$VERSION = '1.0';

# Get the base name of this script.
use File::Basename;
$PROGNAME = basename( $0 );

# Get script path.
my $script_path = $0;
$script_path =~ s/$PROGNAME//g;

# Library directory.
my $library_dir = "ZMPLibs/Lib.pm";
my $ZMPLibs     = "$script_path" . "$library_dir";

require $ZMPLibs;

###############################################################################
# Define and get the command line options.
# see the command line option guidelines at
# https://nagios-plugins.org/doc/guidelines.html#PLUGOPTIONS

# Instantiate Monitoring::Plugin object (the 'usage' parameter is mandatory).
my $mp = Monitoring::Plugin->new(
	usage => "
Usage:
%s [-H <host>] -P <port> [-z <zapikey>] [-f <farm name>] -s <service ID>
[-w <ESTABLISHED,PENDING>] [-c <ESTABLISHED,PENDING>] -v -t <timeout> -T <cache timeout> -n <disable cache> -d <debug>",
	version => $VERSION,
	blurb =>
	  'Check status, established connections and pending connections of backend server in a ZEVENET Load Balancer.',
	extra => "\nExample: \n"
	  . "./$PROGNAME -H 192.168.103.170 -z monitorkey -f farm-test -s serv1 -w 20,20 -c 25,25\n",
	url =>
	  "https://github.com/zevenet/zevenet-monitoring-plugins/blob/master/libexec/$PROGNAME",
	shortname => "ZEVENET"
);

# Define and document the valid command line options
# usage, help, version, timeout and verbose are defined by default.

# Options
# Host
$mp->add_arg(
	spec => 'host|H=s',
	help => qq{-H, --host=STRING
   ZEVENET Load Balancer IP address or FQDN hostname.},
	required => 1
);

# Port
$mp->add_arg(
	spec => 'port|P=i',
	help => qq{-P, --port=INTEGER
   ZEVENET Load Balancer Port.},
	required => 0
);

# ZAPI_KEY
$mp->add_arg(
	spec => 'zapikey|z=s',
	help => qq{-z, --zapikey=STRING
   ZEVENET API v4.0 ZAPI_KEY},
	required => 1
);

# FARM name
$mp->add_arg(
	spec => 'farmname|f=s',
	help => qq{-f, --farmname=STRING
   Farm name.},
	required => 1
);

# Service ID
$mp->add_arg(
	spec => 'service|s=s',
	help => qq{-s, --service=STRING
   Service ID.},
	required => 0,
);

# WARNING threshold
$mp->add_arg(
	spec => 'warning|w=s@',
	help => qq{-w, --warning=ESTABLISHED,PENDING
   Minimum and maximum number of established and pending connections, outside of
   which a warning will be generated.},
	required => 1
);

# CRITICAL threshold
$mp->add_arg(
	spec => 'critical|c=s@',
	help => qq{-c, --critical=ESTABLISHED,PENDING
   Minimum and maximum number of established and pending connections, outside of
   which a critical will be generated.},
	required => 1
);

# Cache timeout
$mp->add_arg(
	spec => 'cache_timeout|T=i',
	help => qq{-T, --cache_timeout=INTEGER
   During this time the data is obtained from a unique request (default: 60) },
	required => 0,
	default  => 60
);

# Disable cache
$mp->add_arg(
	spec => 'no_cache|n',
	help => qq{-n, --no_cache
   Disables the cache. Note that this API request overloads the ZEVENET load balancer. },
	required => 0
);

# Debug
$mp->add_arg(
	spec => 'debug|d',
	help => qq{-d, --debug
    Sends logs information to Syslog file },
	required => 0
);

# Maintenance
$mp->add_arg(
	spec => 'maintenance|m',
	help => qq{-m, --maintenance
    Set warning for maintenance status },
	required => 0
);

# Parse arguments and process standard ones (e.g. usage, help, version).
$mp->getopts;

#############
# VARIABLES #
#############

my $debug         = "true" if ( defined $mp->opts->debug );
my $zapi_version  = "v4.0";
my $host          = $mp->opts->host;
my $farmname      = $mp->opts->farmname;
my $port          = $mp->opts->port // 444;
my $zapikey       = $mp->opts->zapikey;
my $timeout       = $mp->opts->timeout;
my $service_id    = $mp->opts->service;
my $maintenance   = "false";
my $cache         = "true";
my $cache_file    = "/tmp/backend-cache-${host}-${farmname}";
my $lock_cache    = "/tmp/backend-cache-${host}-${farmname}.lock";
my $cache_tiemout = 60;

# Shows the current farm status, their backend status and connections. Each farm will response with a different object, depending on the profile.
# https://www.zevenet.com/zapidocv4.0/#show-farm-statistics
my $url = "/zapi/$zapi_version/zapi.cgi/stats/farms/$farmname";

my %params = (
			   'zapikey' => $zapikey,
			   'host'    => $host,
			   'port'    => $port,
			   'timeout' => $timeout,
			   'url'     => $url
);
my $params_ref = \%params;

# Get warning and critical parameters.
my @warning  = split ( ",", $mp->opts->warning->[0] );
my @critical = split ( ",", $mp->opts->critical->[0] );
my $warningSize  = @warning;
my $criticalSize = @critical;

# Perform sanity check on command line options.
if ( $warningSize != 2 or $criticalSize != 2 )
{
	$mp->nagios_die(
		"*** Not allowed more than two parameters in the warning and critical thresholds.\n"
	);
}
if ( $warning[0] >= $critical[0] or $warning[1] >= $critical[1] )
{
	$mp->nagios_die( "*** CRITICAL level must be greater than WARNING!\n" );
}

# Check cache.
$cache = "false" if ( defined $mp->opts->no_cache );
$cache_tiemout = $mp->opts->cache_timeout
  if ( defined $mp->opts->cache_timeout );

# Set warning for maintenance status.
$maintenance = "true" if ( defined $mp->opts->maintenance );

use Switch;

switch ( $cache )
{
	case "false"
	{
		&sendLogs( $debug, "Cache disabled" );

		# Get JSON with data from all backends.
		my $json_response = &zapiCall( $params_ref, $mp );

		# Check if the service exists.
		&checkService( $json_response, $service_id, $mp );

		# Get farm profile.
		my $farmprofile = &getFarmProfile( $json_response, $service_id, $mp );

		# Get Backend data.
		my @backend_data =
		  &getBackendData( $json_response, $farmprofile, $service_id, $mp );

		# Add performance data.
		unless ( $farmprofile eq "gslb" )
		{
			foreach my $bck ( @backend_data )
			{
				&addPerfdata( $bck, \@warning, \@critical, $mp );
			}
		}

		# Show the result and exit.
		my ( $output_code, $msg ) =
		  &processResults( \@backend_data, \@warning, \@critical,
						   $farmname,      $maintenance );
		$mp->nagios_exit( return_code => $output_code, message => $msg, );
	}
	case "true"
	{
		&sendLogs( $debug, "Cache enabled" );

		# Lock cache.
		my $fh = &lockResource( $lock_cache, "l" );

		my $expired_cache = &checkCacheExpired( $cache_file, $cache_tiemout, $debug );
		if ( $expired_cache eq "true" )
		{
			&sendLogs( $debug, "The cache expired" );

			# Get JSON with data from all backends.
			my $json_response = &zapiCall( $params_ref, $mp );

			# Caching data.
			&saveZapiCall( $json_response, $cache_file, $debug );

			# Unlock cache.
			&lockResource( $lock_cache, "ud", $fh );

			# Check if the service exists.
			&checkService( $json_response, $service_id, $mp );

			# Get farm profile.
			my $farmprofile = &getFarmProfile( $json_response, $service_id, $mp );

			# Get Backend data.
			my @backend_data = &getBackendData( $json_response, $farmprofile, $service_id );

			# Add performance data.
			unless ( $farmprofile eq "gslb" )
			{
				foreach my $bck ( @backend_data )
				{
					&addPerfdata( $bck, \@warning, \@critical, $mp );
				}
			}

			# Show the result and exit.
			my ( $output_code, $msg ) =
			  &processResults( \@backend_data, \@warning, \@critical,
							   $farmname,      $maintenance );
			$mp->nagios_exit( return_code => $output_code, message => $msg, );
		}
		else
		{
			&sendLogs( $debug, "Using cache" );

			# Unlock cache.
			&lockResource( $lock_cache, "ud", $fh );

			# Get JSON with data from all backend (using cache).
			my ( $output_error, $json_response ) = &getCacheData( $cache_file, $debug );

			# Check if the service exists.
			&checkService( $json_response, $service_id, $mp );

			# Get farm profile.
			my $farmprofile = &getFarmProfile( $json_response, $service_id, $mp );

			# Get Backend data.
			my @backend_data = &getBackendData( $json_response, $farmprofile, $service_id );

			# Add performance data.
			unless ( $farmprofile eq "gslb" )
			{
				foreach my $bck ( @backend_data )
				{
					&addPerfdata( $bck, \@warning, \@critical, $mp );
				}
			}

			# Show the result and exit.
			my ( $output_code, $msg ) =
			  &processResults( \@backend_data, \@warning, \@critical,
							   $farmname,      $maintenance );
			$mp->nagios_exit( return_code => $output_code, message => $msg, );
		}
	}
}
