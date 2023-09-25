#!/usr/bin/perl -w
#
# check_tenplate
#
# This module is free software; you can redistribute it and/or modify it
# under the terms of GNU general public license (gpl) version 3.
# See the LICENSE file for details.

use strict;
use Data::Dumper;

our $VERSION = '0.1';

use Nagios::Monitoring::Plugin::Getopt;
# use Nagios::Monitoring::Plugin::Threshold;
# use Nagios::Monitoring::Plugin::Config;
use Nagios::Monitoring::Plugin;

use vars qw(
  $plugin
  $options
  $code
  $message
);

if ( !caller ) {
  run();
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
  $plugin = Nagios::Monitoring::Plugin->new( shortname => 'CHECK_GLANCE' );

  my $usage = <<'EOT';
check_device_mounted [-H|--host <HOST|IP>]
             [-h|--help] [-V|--version] [--usage] [--debug] [--verbose]
EOT

  $options = Nagios::Monitoring::Plugin::Getopt->new(
    usage   => $usage,
    version => $VERSION,
    blurb   => 'Check template'
  );

  $options->arg(
    spec     => 'host|H=s',
    help     => 'API glance server',
    default  => 'localhost',
    required => 1,
  );

  $options->arg(
    spec     => 'debug',
    help     => 'debugging output',
    required => 0,
  );

  $options->getopts();

  $plugin->nagios_exit( 'OK', "OK" );

}
