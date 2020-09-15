# ZEVENET Monitoring Plugins

Monitor plugin collection is written in Perl to monitor ZEVENET ADC Load Balancer Enterprise Edition system health check and performance.

zevenet-monitoring-plugins contains some scripts and a global library which is implemented for offering cache in requests, a request is done
once and along a short period of time (by default 60 seconds) the data is obtained of this cache instead of sending requests to the API,
the idea is to avoid overloading the ZEVENET Load Balancer with a bunch of requests in case the user is monitoring several farms taking into account
that the connection statistics are not going to change significantly in this period of time (60 seconds).


| Plugin                             | Check             | Provided performance data                                                  |
| ---------------------------------- | ----------------- | ---------------------------------------------------------------------------|
| check_zevenet_farm.pl              | Farm status       | Established and pending connections to the farm                            | 
| check_zevenet_farm_backend.pl      | Backend status    | Established and pending connections to the backends                        | 


The plugins are also compatible with Icinga, Naemon, Shinken, Sensu, and other monitoring applications.

Plugins provide performance data, so you can use PNP4Nagios (https://docs.pnp4nagios.org/) or similar tool to make graphs from 
collected metrics.

## INSTALLATION

ZEVENET Monitoring Plugins are developed to be installed in your Icinga (Or Icinga plugin's compatible like Naemon, Shinken, Sensu, and other monitoring applications.) monitoring server. So please access via SSH to
your monitoring host as root to install the required software.

### 1. Install dependencies

Install required perl modules:

#### Debian Buster:

```
apt update && apt install libwww-perl libjson-perl libmonitoring-plugin-perl libswitch-perl
```

If Perl modules don't exist in your distribution package manager, then you can install manually:

#### Other distributions:

```
cpan install LWP::UserAgent
cpan install Monitoring::Plugin
cpan install JSON
cpan install Switch
```

### 2. Decompress ZEVENET Monitoring plugins pack

```
wget https://github.com/zevenet/zevenet-monitoring-plugins/archive/master.zip 
unzip master.zip
```

### 3. Copy check scripts to /usr/lib/nagios/plugins

```
cd zevenet-monitoring-plugins
cp -r libexec/* /usr/lib/nagios/plugins
```

### 4. Create a valid ZAPI v4 key thought ZEVENET ADC Load Balancer web interface

Login into ZEVENET web interface and go to System > Users > Edit zapi user > Generate random key, we'll use this key as an authentication method to retrieve the metrics from ZEVENET ADC Load Balancer appliance.  Finally, make sure the zapi user is active.


### 5. Test plugin manually

```
cd /usr/lib/nagios/plugins
./check_zevenet_farm.pl -H 192.168.103.160 -z monitor-zapikey -f farm-l4 -w 20,20 -c 25,25
```
Example output:

```
ZEVENET OK - profile='l4xnat' farm='farm-l4' listen='192.168.103.191:91' status='up' (established_connections='10') (pending_connections='0') | established_connections=10;20;25 pending_connections=0;20;25
```

For more information please execute the script with --help option.

```
./check_zevenet_farm.pl --help

check_zevenet_farm.pl 1.0 [https://github.com/zevenet/zevenet-monitoring-plugins/blob/master/libexec/check_zevenet_farm.pl]

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
It may be used, redistributed and/or modified under the terms of the GNU
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

Check farm status, established connections and pending connections of a ZEVENET Load Balancer.


Usage:
check_zevenet_farm.pl [-H <host>] -P <port> [-z <zapikey>] [-f <farm name>]
[-w <ESTABLISHED,PENDING>] [-c <ESTABLISHED,PENDING>] -v -t <timeout> -T <cache timeout> -n <disable cache> -d <debug>

 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See https://www.monitoring-plugins.org/doc/extra-opts.html
   for usage and examples.
 -H, --host=STRING
   ZEVENET Load Balancer IP address or FQDN hostname.
 -P, --port=INTEGER
   ZEVENET Load Balancer Port.
 -z, --zapikey=STRING
   Key to authorize the access via ZEVENET API v4.0
 -f, --farmname=STRING
   Farm name.
 -w, --warning=ESTABLISHED,PENDING
   Minimum and maximum number of established and pending connections, outside of
   which a warning will be generated.
 -c, --critical=ESTABLISHED,PENDING
   Minimum and maximum number of established and pending connections, outside of
   which a critical will be generated.
 -T, --cache_timeout=INTEGER
   During this time the data is obtained from a unique request (default: 60) 
 -n, --no_cache
   Disables the cache. Note that this API request overloads the ZEVENET load balancer. 
 -d, --debug
    Sends logs information to Syslog file 
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 15)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)

Example: 
./check_zevenet_farm.pl -H 192.168.103.170 -z monitorkey -f farm-test -w 20,20 -c 25,25
```
These checks are designed to check LSLB and GSLB farms.
Examples:

Monitoring established and pending connections in farm LSLB with profile L4XNAT.
```
./check_zevenet_farm.pl -H 192.168.103.170 -z monitorkey -f farm-l4 -w 20,20 -c 25,25
ZEVENET OK - profile='l4xnat' farm='farm-l4' listen='192.168.103.191:91' status='up' (established_connections='10') (pending_connections='0') | established_connections=10;20;25 pending_connections=0;20;25
```
Monitoring established and pending connections in farm LSLB with profile HTTP.
```
./check_zevenet_farm.pl -H 192.168.103.170 -z monitorkey -f farm-http -w 20,20 -c 25,25
ZEVENET OK - profile='http' farm='farm-http' listen='192.168.103.190:90' status='up' (established_connections='10') (pending_connections='0') | established_connections=10;20;25 pending_connections=0;20;25
```
Monitoring established and pending connections in farm GSLB.
```
./check_zevenet_farm.pl -H 192.168.103.170 -z monitorkey -f farm-gslb -w 20,20 -c 25,25
ZEVENET OK - profile='gslb' farm='farm-gslb' listen='192.168.103.192:53' status='up' (established_connections='10') (pending_connections='0') | established_connections=10;20;25 pending_connections=0;20;25
```

Monitoring established and pending connections in backends of LSLB with profile L4XNAT.
```
./check_zevenet_farm_backend.pl -H 192.168.103.170 -z monitorkey -f farm-l4 -w 20,20 -c 25,25
ZEVENET OK - Backend='192.168.101.254:80' status='up' (established_connections='10') (pending_connections='0')Backend='192.168.102.254:80' status='up' (established_connections='5') (pending_connections='0') | 192.168.101.254_established=10;20;25 192.168.101.254_pending=0;20;25 192.168.102.254_established=5;20;25 192.168.102.254_pending=0;20;25
```
Monitoring established and pending connections in backends of LSLB with profile HTTP in service serv1.
```
./check_zevenet_farm_backend.pl -H 192.168.103.170 -z monitorkey -f farm-http -s serv1 -w 20,20 -c 25,25
ZEVENET OK - Backend='192.168.101.254:80' status='up' (established_connections='10') (pending_connections='0')Backend='192.168.103.254:80' status='up' (established_connections='5') (pending_connections='0') | 192.168.101.254_established=10;20;25 192.168.101.254_pending=0;20;25 192.168.103.254_established=5;20;25 192.168.103.254_pending=0;20;25
```
Monitoring established and pending connections in backends of LSLB in service serv3.
```
./check_zevenet_farm_backend.pl -H 192.168.103.170 -z monitorkey -f farm-gslb -s serv3 -w 20,20 -c 25,25
ZEVENET OK - Backend='192.168.102.254:80' status='up' Backend='192.168.101.254:80' status='up'
```

### 6. Add command definitions to Icinga

See Icinga command definitions example file in “icinga/icinga_commands.cfg” .

You can add the command definitions to your Icinga configuration:

```
cd icinga/
cat icinga_commands.cfg >> /usr/share/icinga2/include/command-plugins.conf
```

### 7. Add service definitions to Icinga

See Icinga service definitions example file in “icinga/icinga_services.cfg” .

You can add the service definitions to your Icinga configuration:

```
cd icinga/
cat icinga_services.cfg >> /etc/icinga2/conf.d/services.conf
```
### 8. Restart Icinga and have fun!

Restart Icinga process and access Icinga web interface to see the services you have just created.

```
/etc/init.d/icinga2 restart
```

## CONSIDERATIONS

If you need to check CPU, disk, memory, etc... then we recommend using SNMP protocol or NRPE protocol. For more information about how to use SNMP protocol please refer to this article:

https://www.zevenet.com/knowledge-base/howtos/understanding-snmp-in-a-siem-environment-and-monitoring-zevenet-appliance/

For more information about how to use NRPE protocol please refer to this article:

https://icinga.com/docs/icinga1/latest/en/nrpe.html
