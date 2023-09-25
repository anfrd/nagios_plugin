#!/usr/bin/perl -w
#
# check_neutron
#
# This module is free software; you can redistribute it and/or modify it
# under the terms of GNU general public license (gpl) version 3.
# See the LICENSE file for details.

use strict;
use HTTP::Request;
use JSON qw(from_json to_json);
use LWP;
use Cache::File;
use Data::Dumper;

our $VERSION = '0.1';

use Nagios::Monitoring::Plugin::Getopt;
use Nagios::Monitoring::Plugin::Threshold;
use Nagios::Monitoring::Plugin::Config;
use Nagios::Monitoring::Plugin;

use vars qw(
  $plugin
  $options
  $user
  $tenant
  $passwd
  $authurl
  $code
  $message
);

if ( !caller ) {
    run();
}

sub _agent {
    my $self = shift;
    my $agent = LWP::UserAgent->new(
	ssl_opts => { verify_hostname => 0 });
    return $agent;
}

sub _url {
    my ($self, $path, $is_detail, $query) = @_;
    my $url = 'http://' . $self . $path;
    $url .= '/detail' if $is_detail;
    $url .= $query if $query;
    verbose ("_URL: URL = $url\n", 3);
    return $url;
}

sub _post {
    my ($url, $data) = @_;    
    my $res =  _agent->post(
        $url,
        content_type => 'application/json',
        content      => to_json($data),
    );
    $plugin->nagios_die("WARNING: " . $res->status_line) unless $res->is_success;
    return $res;
}

sub _get {
    my ($url, $aurl) = @_;
    my $res = _agent->get($url, 'X-Auth-Token' => get_token($aurl));
    $plugin->nagios_die("ERROR: " . $res->status_line) unless $res->is_success;
    return $res;
}

sub get_token {
    my ($url) = @_;
    my $token = _cache()->get('token');
    unless ($token) {
	my $data = from_json(_post(_url($url, ":5000/v2.0/tokens"), {auth => { tenantName => $tenant, passwordCredentials => { username => $user, password => $passwd }}})->content);
	$token = $data->{access}{token}{id};
	_cache()->set('token', $token, '86400 sec');
	verbose ("Cache missing or expire; get token from keystone\n", 3);
    }
    verbose ("GET_TOKEN: Token = $token\n", 3);
    return $token;
}

sub get_agents {
    my ($url, $aurl) = @_;
    my $res = _get(_url($url, ":9696/v2.0/agents"), $aurl);    
    return $res->content;
}

sub _cache {
    my $self = shift;
    my $cache = Cache::File->new( cache_root => $options->cache,
				  default_expires => '86400 sec');
    return $cache;
}

sub verbose {
    # arguments
    my $message = shift;
    my $level   = shift;

    if ( !defined $message ) {
        $plugin->nagios_exit( UNKNOWN,
            q{Internal error: not enough parameters for 'verbose'} );
    }

    if ( !defined $level ) {
        $level = 0;
    }

    if ( $options->debug() ) {
        print '[DEBUG] ';
    }

    if ( $level < $options->verbose() || $options->debug() ) {
        print $message;
    }

    return;
}

sub run {
     $plugin = Nagios::Monitoring::Plugin->new( shortname => 'CHECK_NEUTRON' );

     my $usage = <<'EOT';
check_device_mounted [-H|--host <HOST|IP>] [-A|--authurl <HOST|IP>] [-u|--user] [-T|--tenant] [-p|--passwd] [-P|--port] [-C|--config <path/to/config>] [--cache <path/to/cache>] [-t|--timeout] 
             [-h|--help] [-V|--version] [--usage] [--debug] [--verbose]
EOT
        
     $options = Nagios::Monitoring::Plugin::Getopt->new(
        usage   => $usage,
        version => $VERSION,
        blurb   => 'Check neutron server'
     );

     $options->arg(
        spec     => 'host|H=s',
        help     => 'API neutron server',
	default  => 'localhost',
        required => 1,
     );

     $options->arg(
        spec     => 'authurl|A=s',
        help     => 'Auth URL to keystone server',
	default  => 'localhost',
        required => 0,
     );

     $options->arg(
        spec     => 'port|P=s',
        help     => 'Auth URL to keystone port',
	default  => '5000',
        required => 0,
     );


     $options->arg(
        spec     => 'user|u=s',
        help     => 'user name',
        required => 0,
     );

     $options->arg(
        spec     => 'tenant|T=s',
        help     => 'tenant name',
        required => 0,
     );

     $options->arg(
        spec     => 'passwd|p=s',
        help     => 'user password',
        required => 0,
     );

     $options->arg(
        spec     => 'config|C=s',
        help     => qq{'Config file with user and password like plugin.ini file. 
        Example:
          [compute]
          user=username
          tenant=tenantname
          password=supersecretpass
          keystone=hostname.keystone.api'},
        required => 0,
     );

     $options->arg(
        spec     => 'cache=s',
        help     => 'Cache dir (default: /tmp/check_ganglia)',
        default  => '/run/shm/keystone_auth',
        required => 0,
     );

     $options->arg(
        spec     => 'debug',
        help     => 'debugging output',
        required => 0,
     );
     
     $options->getopts();

     if ($options->config) {
	 my $Config = Nagios::Monitoring::Plugin::Config->read( $options->config )
	     or $plugin->nagios_die("Cannot read config file " . $options->config);
	 $user = $Config->{compute}->{user}[0];
	 $tenant = $Config->{compute}->{tenant}[0];
	 $passwd = $Config->{compute}->{password}[0];
	 $authurl = $Config->{compute}->{keystone}[0];
	 verbose ("User: $user;\n", 3); 
         verbose ("Tenant: $tenant;\n", 3); 
         verbose ("Passwd: $passwd;\n", 3); 
	 verbose ("Auth url: $authurl\n", 3);
     } elsif (($options->user) && ($options->passwd)) {
	 $user = $options->user;
	 $tenant = $options->tenant;
	 $passwd = $options->passwd;
	 $authurl = $options->authurl;
	 verbose ("User: $user;\n", 3); 
         verbose ("Tenant: $tenant;\n", 3); 
         verbose ("Passwd: $passwd;\n", 3); 
	 verbose ("Auth url: $authurl\n", 3);
     } else {
	 $plugin->nagios_die("One of arguments need definition: [-u <user> -T <tenant> -p <passwd> -A <authurl>] | [-C config.ini]");
     }

     my @agents = from_json(get_agents($options->host, $authurl))->{'agents'};     
     my $all_agents = 0;
     my $alive = 0;
     foreach my $a ( @{$agents[0]} ) {
	 if ($a->{'binary'} eq 'neutron-openvswitch-agent') {
	     $all_agents += 1;
	     if ($a->{'alive'}) {
		 $alive += 1;
	     }
	 }
     }

     if ($all_agents == 0) {
	 $plugin->nagios_exit( 'CRITICAL', "Agents were obtained." );
     } elsif ($alive == 0) {
	 $plugin->nagios_exit( 'CRITICAL', "All agents are not be alive." );
     } else {
	 $plugin->nagios_exit( 'OK', "OK" );
     }
}
