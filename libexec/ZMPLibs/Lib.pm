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

use strict;
use warnings;
use Data::Dumper;

=begin nd
Function: sendLogs

	Function to print debug messages in syslog.

Parameters:
	Mode - "true" if enabled.
	String - String to print.

Returns:
	None.
=cut

sub sendLogs()
{
	my $debug = shift;
	my $msg   = shift;

	use Sys::Syslog;
	syslog( "LOG_INFO", "***** $msg *****" ) if ( defined $debug );

	return;
}

=begin nd
Function: lockResource

	lock or release a resource.

Parameters:
	resource - Path to file.
	operation - l (lock), u (unlock) ,ud (unlock, delete the lock file).
	FILEHANDLER - FIle descriptor used to unlock the resource.

Returns:
	0 - On success.
	1 - On failure.
=cut

sub lockResource
{
	my $resource = shift;
	my $oper     = shift; # l (lock), u (unlock) ,ud (unlock, delete the lock file).
	my $fh       = shift;
	my $error    = 0;

	if ( $oper =~ /l/ )
	{
		open ( $fh, ">", "$resource" ) || do { $error = 1; };
		if ( $error == 0 )
		{
			# Exclusive lock for writing.
			flock $fh, LOCK_EX;
		}
	}
	elsif ( $oper =~ /u/ )
	{
		close ( $fh );
		unlink $resource if ( $oper =~ /d/ );
	}

	return $fh;
}

=begin nd
Function: checkCacheExpired

	Checks if the cache has expired.

Parameters:
	String - Full path of the file used as a cache.
	Integer - Time in seconds the cache expires.
	$debug - Prints debug messages in syslog if debug is true.

Returns:
	String - "true" if the cache has expired or "false" if the cache has not expired.
=cut

sub checkCacheExpired()
{
	my $file          = shift;
	my $cache_tiemout = shift;
	my $debug         = shift;
	my $expired       = "false";

	if ( -f $file )
	{
		# Calculate the last modification of the $cache_file, time in second.
		my $mtime        = ( stat $file )[9];
		my $current_time = time;
		my $diff         = $current_time - $mtime;

		&sendLogs( $debug, "Last use cache = $diff" );
		&sendLogs( $debug, "cache timeout = $cache_tiemout" );

		$expired = "true" if ( $diff >= $cache_tiemout );
	}
	else
	{
		$expired = "true";
	}

	return $expired;
}

=begin nd
Function: saveZapiCall

	Saves the HTTPS response in a file (used as cache).

Parameters:
	Hash ref - Json with the response data. Refer to zapiCall doc for further information.
	String - Full path of the file used as a cache.
	$debug - Prints debug messages in syslog if debug is true.

Returns:
	0 - On success.
	1 - On failure.
=cut

sub saveZapiCall()
{
	my $params = shift;
	my $file   = shift;
	my $debug  = shift;
	my $error  = 0;

	# Encoding JSON.
	my $content = JSON->new->utf8( 1 )->pretty( 1 )->encode( $params );

	# Saves the data to a file.
	open ( my $fh, ">", "$file" ) || do { $error = 1; };

	if ( $error == 0 )
	{
		# Exclusive lock for writing.
		flock $fh, LOCK_EX;
		print $fh $content;
		close ( $fh );
	}
	else
	{
		&sendLogs( $debug,
				   "Error openning the file $file, please, check file permissions" );
		print
		  "***** Error openning the file $file, please, check file permissions *****\n";
	}

	return $error;
}

=begin nd
Function: zapiCall

	It execute an HTTPS request to the load balancer ZAPI service.

Parameters:
	Hash ref - It's a hash reference with the required parameters to create a ZAPI request. The required parameters are:
				zapikey, key to authorize the access via ZEVENET API.
				host, ZEVENET Load Balancer IP address or FQDN hostname.
				port, ZEVENET Load Balancer Port.
				timeout, maximum time the request should take.
				url, request.
	$mp	- It's the monitoring plugin object.

Returns:
	$json_response - Returns a json with the response from the ZAPI.
=cut

sub zapiCall()
{
	my $params        = shift;
	my $mp            = shift;
	my $zapikey       = $params->{ 'zapikey' };
	my $host          = $params->{ 'host' };
	my $port          = $params->{ 'port' };
	my $timeout       = $params->{ 'timeout' };
	my $url           = $params->{ 'url' };
	my $ua            = LWP::UserAgent->new;
	my $json_response = '';

	$ua->ssl_opts( verify_hostname => 0, SSL_verify_mode => 0x00 );

	# Maximum time the request should take.
	$ua->timeout( $timeout );

	# Protocols allowed.
	$ua->protocols_allowed( ['https'] );
	$ua->default_header( 'Content-Type' => 'application/json' );
	$ua->default_header( 'ZAPI_KEY'     => "$zapikey" );

	my $request = HTTP::Request->new( GET => "https://$host:$port$url" );
	my $response = $ua->request( $request );

	if ( $response->is_success )
	{
		# Decoding JSON.
		$json_response = decode_json( $response->content );

		# Parse JSON.
		if ( $mp->opts->verbose )
		{
			print Dumper ( "Request:",  $request );
			print Dumper ( "------------------------------------" );
			print Dumper ( "Response:", $response );
		}
	}

	# Wrong ZAPI key.
	if ( defined $response->{ '_msg' } )
	{
		if ( $response->{ '_msg' } eq 'Authorization Required' )
		{
			$mp->nagios_exit(
				return_code => CRITICAL,
				message =>
				  "The authentication failed. Please, review the following settings\n*) The zapi user is enabled: clicking on ZEVENET Webgui 'System > User'."
			);
		}
	}

	# Add message for error.
	unless ( $response->is_success )
	{
		$mp->nagios_exit(
				  return_code => UNKNOWN,
				  message =>
					"There was an error in the load balancer. The command could not finish."
		);
	}

	return $json_response;
}

=begin nd
Function: checkFarm

	Checks if the farm exists.

Parameters:
	Hash ref - Json with the data of all farms. Refer to zapiCall doc for further information.
	String - Farm name to check.
	$mp	- It's the monitoring plugin object.

Returns:
	None.
=cut

sub checkFarm()
{
	my $params     = shift;
	my $name       = shift;
	my $mp         = shift;
	my $farm       = "";
	my $farm_found = 1;
	my $farms      = $params->{ 'farms' };

	foreach $farm ( @$farms )
	{
		if ( $farm->{ 'farmname' } eq $name )
		{
			$farm_found = 0;
			last;
		}
	}

	if ( $farm_found != 0 )
	{
		$mp->nagios_exit( return_code => CRITICAL,
						  message     => "farm '$name' not found!" );
	}

	return;
}

=begin nd
Function: checkServie

	Checks if the service exists.

Parameters:
	Hash ref - Json with the data of all backends. Refer to zapiCall doc for further information.
	String - Service name to check.
	$mp	- It's the monitoring plugin object.

Returns:
	None.
=cut

sub checkServie()
{
	my $params        = shift;
	my $name          = shift;
	my $mp            = shift;
	my $service       = "";
	my $service_found = 1;
	my $backends      = $params->{ 'backends' };

	unless ( !defined $name )
	{
		foreach my $bck ( @$backends )
		{
			if ( defined $bck->{ 'service' } and $bck->{ 'service' } eq $name )
			{
				$service_found = 0;
				last;
			}
		}

		if ( $service_found != 0 )
		{
			$mp->nagios_exit( return_code => CRITICAL,
							  message     => "service '$name' not found!" );
		}
	}

	return;
}

=begin nd
Function: getFarmProfile

	Checks the profile of farm, HTTP, L4XNAT or GSLB.

Parameters:
	Hash ref - Json with the backend data. Refer to zapiCall doc for further information.
	$service_id - Variable that checks if the service id is defined in the command line options.
	$mp	- It's the monitoring plugin object.

Returns:
	String - Return "http", "l4xnat" or "gslb".
=cut

sub getFarmProfile()
{
	my $params       = shift;
	my $service_id   = shift;
	my $mp           = shift;
	my $backend      = "";
	my $backends     = $params->{ 'backends' };
	my $farm_profile = "";

	if ( defined $params->{ 'client' } )
	{
		$farm_profile = "gslb";

		# Checks that the service id exists in the command line options.
		if ( !defined $service_id )
		{
			$mp->nagios_die(
				"*** In gslb farms it is necessary to indicate the ID of the service to monitor. *****\n"
			);
		}
	}
	else
	{
		foreach $backend ( @$backends )
		{
			if ( defined $backend->{ 'service' } )
			{
				$farm_profile = "http";

				# Checks that the service id exists in the command line options.
				if ( !defined $service_id )
				{
					$mp->nagios_die(
						"*** In http farms it is necessary to indicate the ID of the service to monitor. *****\n"
					);
				}

				last;
			}
			else
			{
				$farm_profile = "l4xnat";
				last;
			}
		}

	}

	return $farm_profile;
}

=begin nd
Function: getFarmData

	Gets the farm data.

Parameters:
	Hash ref - Json with the farm data. Refer to zapiCall doc for further information.
	String - Name of the farm to obtain the data.

Returns:
	Hash ref - Returns the requested farm data.
			   Example:
			   {
			     'farm' => '',
			     'profile' => 'http',
			     'status' => 'up',
			     'pending' => 0,
			     'established' => 0,
			     'vip' => '192.168.101.131',
			     'vport' => '92'
			   };
=cut

sub getFarmData()
{
	my $params = shift;
	my $name   = shift;
	my $farm   = "";
	my %farm_def = (
					 'farm'        => '',
					 'established' => '',
					 'pending'     => '',
					 'profile'     => '',
					 'status'      => '',
					 'vip'         => '',
					 'vport'       => ''
	);
	my $farm_ref = \%farm_def;
	my $farms    = $params->{ 'farms' };

	# Search farm entered by parameters.
	foreach $farm ( @$farms )
	{
		if ( $farm->{ 'farmname' } eq $name )
		{
			$farm_ref->{ established } = $farm->{ 'established' };
			$farm_ref->{ pending }     = $farm->{ 'pending' };
			$farm_ref->{ profile }     = $farm->{ 'profile' };
			$farm_ref->{ status }      = $farm->{ 'status' };
			$farm_ref->{ vip }         = $farm->{ 'vip' };
			$farm_ref->{ vport }       = $farm->{ 'vport' };
			last;
		}
	}

	return $farm_ref;
}

=begin nd
Function: getCacheData

	Gets the farms data from a file (used as cache).

Parameters:
	String - Full path of the file used as a cache.
	$debug - Prints debug messages in syslog if debug is true.

Returns:
	Integer - 0 on success or 1 on failure.
	Hash ref - Returns a Json with the data from the file.
=cut

sub getCacheData()
{
	my $file          = shift;
	my $debug         = shift;
	my $content       = "";
	my $json_response = "";
	my $error         = 0;

	open ( my $fh, "<", "$file" ) || do { $error = 1; };

	if ( $error == 0 )
	{
		# Exclusive lock for reading.
		flock $fh, LOCK_SH;
		{
			local $/;
			$content = <$fh>;
		}
		close ( $fh );
	}
	else
	{
		&sendLogs( $debug,
				   "Error getting cache data, please, check $file file permissions" );
		print
		  "***** Error getting cache data, please, check $file file permissions *****\n";
	}

	# Decoding JSON.
	$json_response = decode_json( $content );

	return $error, $json_response;
}

=begin nd
Function: getBackendData

	Gets the backend data.

Parameters:
	Hash ref - Json with the backend data. Refer to zapiCall doc for further information.
	String - Farm profile, "http", "l4xnat" or "gslb".
	String - Service ID if the farm is of type "http" or "gslb" and nothing if it is of type l4xnat.

Returns:
	Array ref - Array of references to hashes, each hash contains the data of a backend.
				Example:
				{
					'status' => 'up',
					'pending' => 0,
					'port' => 80,
					'established' => 20,
					'ip' => '192.168.101.254'
				},
				{
					'port' => 80,
					'ip' => '192.168.103.254',
					'established' => 20,
					'pending' => 0,
					'status' => 'up'
				}
=cut

sub getBackendData()
{
	my $params       = shift;
	my $farm_profile = shift;
	my $service_id   = shift;
	my $mp           = shift;
	my $backend      = "";
	my @all_backends = ();

	my $backends = $params->{ 'backends' };

	if ( $farm_profile eq "l4xnat" )
	{
		foreach $backend ( @$backends )
		{
			my $backend_ref;
			$backend_ref->{ established } = $backend->{ 'established' };
			$backend_ref->{ pending }     = $backend->{ 'pending' };
			$backend_ref->{ status }      = $backend->{ 'status' };
			$backend_ref->{ ip }          = $backend->{ 'ip' };
			$backend_ref->{ port }        = $backend->{ 'port' };

			push @all_backends, $backend_ref;
		}
	}
	else
	{
		foreach $backend ( @$backends )
		{
			my $backend_ref;
			if (     defined $service_id
				 and defined $backend->{ 'service' }
				 and $backend->{ 'service' } eq $service_id )
			{
				if ( $farm_profile eq "gslb" )
				{
					$backend_ref->{ status } = $backend->{ 'status' };
					$backend_ref->{ ip }     = $backend->{ 'ip' };
					$backend_ref->{ port }   = $backend->{ 'port' };

					push @all_backends, $backend_ref;
				}
				if ( $farm_profile eq "http" )
				{
					$backend_ref->{ established } = $backend->{ 'established' };
					$backend_ref->{ pending }     = $backend->{ 'pending' };
					$backend_ref->{ status }      = $backend->{ 'status' };
					$backend_ref->{ ip }          = $backend->{ 'ip' };
					$backend_ref->{ port }        = $backend->{ 'port' };

					push @all_backends, $backend_ref;
				}
			}
		}
	}

	return @all_backends;
}

=begin nd
Function: addPerfdata

	Adds performance data. Established connections and pending connections.

Parameters:
	hash_ref - Established or pending connections from the farm or backend. refer to gerFarmData or getBackendData doc for further information.
	$mp	- It's the monitoring plugin object.

Returns:
	none.
=cut

sub addPerfdata()
{
	my $params   = shift;
	my $warning  = shift;
	my $critical = shift;
	my $mp       = shift;
	my $emsg     = "established_connections";
	my $pmsg     = "pending_connections";
	my $ip       = "";

	if ( defined $params->{ 'ip' } )
	{
		$ip   = $params->{ 'ip' };
		$emsg = $ip . "_established";
		$pmsg = $ip . "_pending";
	}

	# Perfdata methods.
	$mp->add_perfdata(
		label => $emsg,
		value => $params->{ 'established' },

		warning  => @{ $warning }[0],
		critical => @{ $critical }[0],
	);

	$mp->add_perfdata(
		label => $pmsg,
		value => $params->{ 'pending' },

		warning  => @{ $warning }[1],
		critical => @{ $critical }[1],
	);

	return;
}

=begin nd
Function: checkCode

	Checks OK, WARNING or CRITICAL error code.

Parameters:
	hash_ref - Contains the farm or backend data, refer to gerFarmData or getBackendData doc for further information.

Returns:
	String - Returns OK, WARNING or CRITICAL.
=cut

sub checkCode()
{
	my $params   = shift;
	my $warning  = shift;
	my $critical = shift;
	my $code     = "";

	# Check established and pending connections.
	if ( defined $params->{ 'established' } and defined $params->{ 'pending' } )
	{
		$code = "WARNING"  if $params->{ 'established' } >= @{ $warning }[0];
		$code = "WARNING"  if $params->{ 'pending' } >= @{ $warning }[1];
		$code = "CRITICAL" if $params->{ 'established' } >= @{ $critical }[0];
		$code = "CRITICAL" if $params->{ 'pending' } >= @{ $critical }[1];
	}

	# Check status.
	$code = "CRITICAL" if $params->{ 'status' } ne "up";

	$code = "OK" if ( $code eq "" );

	return $code;
}

=begin nd
Function: processResults

	Processes the results.

Parameters:
	Array ref or hash ref - Contains the farm or backend data, refer to gerFarmData or getBackendData doc for further information.
	array - Warning parameters.
	array - Critical parameters.
	String - Farm name.

Returns:
	String - Returns OK, WARNING or CRITICAL.
	String - Returns a output message.
=cut

sub processResults()
{
	my $params   = shift;
	my $warning  = shift;
	my $critical = shift;
	my $farmname = shift;
	my $status   = "";
	my $code     = "";
	my $msg      = "";

	if ( ref $params eq 'ARRAY' )
	{
		$code = "OK";
		foreach my $bck ( @{ $params } )
		{
			$msg = "$msg"
			  . ", Backend='$bck->{'ip'}:$bck->{'port'}' "
			  . "status='$bck->{'status'}' ";

			if ( defined $bck->{ 'established' } and defined $bck->{ 'pending' } )
			{
				$msg = "$msg"
				  . "(established_connections='$bck->{'established'}') "
				  . "(pending_connections='$bck->{'pending'}')";
			}

			$status = &checkCode( $bck, $warning, $critical );

			if ( $status ne "OK" )
			{
				$code = $status if ( $code ne "CRITICAL" );
			}
		}
		$msg =~ s/^,\s//;
	}

	if ( ref $params eq 'HASH' )
	{
		$msg =
		    "profile='$params->{ 'profile' }' "
		  . "farm='$farmname' "
		  . "listen='$params->{ 'vip' }:$params->{ 'vport' }' "
		  . "status='$params->{ 'status' }' "
		  . "(established_connections='$params->{ 'established' }') "
		  . "(pending_connections='$params->{ 'pending' }')";

		$code = &checkCode( $params, $warning, $critical );
	}

	return $code, $msg;
}

1;
