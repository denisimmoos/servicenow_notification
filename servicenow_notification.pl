#!/usr/bin/env perl 
#===============================================================================
#
#         FILE: servicenow_notification.pl
#
#        USAGE: ./servicenow_notification.pl  
#
#  DESCRIPTION: nagios/icinga check for graylog
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Denis Immoos (<denisimmoos@gmail.com>)
#    AUTHORREF: Senior Linux System Administrator (LPIC3)
#      VERSION: 1.0
#      CREATED: 11/20/2015 03:21:31 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

use lib '/etc/icinga2/scripts/servicenow_notification/lib';
use Data::Dumper;

#
#===============================================================================
# DEFAULTS 
#===============================================================================

our %Options = ();
$Options{'new_incident'} = 1;
$Options{'icingaweb2_url'} = 'http://10.122.30.40/icingaweb2';
$Options{'servicenow_url'} = 'https://steriadev.service-now.com';
$Options{'servicenow_username'} = 'servicenow'; 
$Options{'servicenow_password'} = 'change_me'; 

$Options{'mysql_host'}     = '127.0.0.1';
$Options{'mysql_port'}     = '3306';
$Options{'mysql_db'}       = 'icinga';
$Options{'mysql_user'}     = 'icinga';
$Options{'mysql_passwd'}   = 'icinga';
# ACK sleep
# teh time achnoledge waits on icinga
$Options{'ack_sleep_time'}   = 1;

# Alle benutzten ENV VARIABELN
$Options{'icinga_env_vars' } = [
	'HOSTDISPLAYNAME',
	'SERVICEDISPLAYNAME',
	'SERVICESTATE',
	'SERVICEOUTPUT',
	'HOSTADDRESS',
	'LONGDATETIME',
	'COMPANY',
	'ASSIGNEMENT_GROUP',
];


#===============================================================================
# SYGNALS 
#===============================================================================

# You can get all SIGNALS by:
# perl -e 'foreach (keys %SIG) { print "$_\n" }'
# $SIG{'INT'} = 'DEFAULT';
# $SIG{'INT'} = 'IGNORE';

sub INT_handler {
    my($signal) = @_;
    chomp $signal;
    use Sys::Syslog;
    my $msg = "INT: int($signal)\n";
    print $msg;
    syslog('info',$msg);
    exit(0);
}
$SIG{INT} = 'INT_handler';

sub DIE_handler {
    my($signal) = @_;
    chomp $signal;
    use Sys::Syslog;
    my $msg = "DIE: die($signal)\n";
    syslog('info',$msg);
}
$SIG{__DIE__} = 'DIE_handler';

sub WARN_handler {
    my($signal) = @_;
    chomp $signal;
    use Sys::Syslog;
    my $msg = "WARN: warn($signal)\n";
    syslog('info',$msg);
}
$SIG{__WARN__} = 'WARN_handler';

#===============================================================================
# OPTIONS
#===============================================================================

use Getopt::Long;
Getopt::Long::Configure ("bundling");
GetOptions(\%Options,
	'v',    'verbose', 
	'h',    'help',
	'HOSTDISPLAYNAME:s',
	'SERVICEDISPLAYNAME:s',
	'SERVICESTATE:s',
	'SERVICEOUTPUT:s',
	'HOSTADDRESS:s',
	'LONGDATETIME:s',
	'COMPANY:s',
	'ASSIGNEMENT_GROUP:s',
);

#===============================================================================
# VARS
#===============================================================================

# store the environment
foreach my $key (keys(%ENV)) {
	    $Options{'ENV'}{$key} = $ENV{$key}; 
}

# move some variables
foreach my $var (@{$Options{'icinga_env_vars'}}) {
	if ($Options{$var}){
	     $Options{'ENV'}{$var} = $Options{$var};
	}
}

#===============================================================================
# SEARCH IN MYSQL FOR MAGIC_COOKIE
#===============================================================================

use IcingaMySQL;
my $IcingaMySQL = IcingaMySQL->new();
# Get the magic_cookie from icinga
%Options = $IcingaMySQL->get_magic_cookie(\%Options);

#===============================================================================
# SEARCH IN MYSQL IF ACKNOWLEGED
#===============================================================================
%Options = $IcingaMySQL->check_ack(\%Options);


#===============================================================================
# SERVICE NOW REST API
#===============================================================================

use ServiceNowREST;
my $ServiceNowREST = ServiceNowREST->new();
%Options = $ServiceNowREST->get_json_result(\%Options);

# delete mysql ticket
# if there is no correlation in servicenow
if ( defined($Options{'IcingaMySQL'}{'sys_id'}) and not defined ($Options{'get_json_result'}{'sys_id'}) ) {
	    %Options = $IcingaMySQL->delete_magic_cookie(\%Options);
		warn "$0 :: incident(deleted): " 
		. $Options{'IcingaMySQL'}{'number'} 
		. " :: " 
		. $Options{'ENV'}{'SERVICESTATE'} 
		. " :: " 
		. $Options{'ENV'}{'HOSTDISPLAYNAME'} 
		. " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'} . "\n";
}

# print Dumper(%Options);
if ($Options{'get_json_result'}{'sys_id'}) {

	%Options = $ServiceNowREST->update_incident(\%Options);

	# Check if incident was created
	if ($Options{'update_incident'}{'number'}) {
		warn "$0 :: incident(updated): " . $Options{'update_incident'}{'number'} . " :: " . $Options{'ENV'}{'SERVICESTATE'} . " :: " . $Options{'ENV'}{'HOSTDISPLAYNAME'} . " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'} . "\n";
	} else {
        die "$0 :: incident(update error): \$Options{update_incident}{number}" . "\n";
	}
	
	if ( $Options{'ENV'}{'SERVICESTATE'} eq 'OK' and defined($Options{'new_incident'}) ) {

		# delete it
	    %Options = $IcingaMySQL->delete_magic_cookie(\%Options);

		if ($Options{'delete_magic_cookie'}{'status'}) {
			warn "$0 :: incident(deleted): " . $Options{'update_incident'}{'number'} . " :: " . $Options{'ENV'}{'SERVICESTATE'} . " :: " . $Options{'ENV'}{'HOSTDISPLAYNAME'} . " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'} . "\n";
		} else {
			die "$0 :: incident(delete error): \$Options{update_incident}{number}" . "\n";
		}
	}

} else {

	if ($Options{'ENV'}{'SERVICESTATE'} ne 'OK' ) {
		# create incident
		%Options = $ServiceNowREST->post_incident(\%Options);

		# Check if incident was created
		if ($Options{'post_incident'}{'number'}) {
			warn "$0 :: incident(created): " . $Options{'post_incident'}{'number'} . " :: " . $Options{'ENV'}{'SERVICESTATE'} . " :: " . $Options{'ENV'}{'HOSTDISPLAYNAME'} . " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'} . "\n";
		} else {
			die "$0 :: incident(create error): \$Options{post_incident}{number}" . "\n";
		}

		# create magic cookie 
		%Options = $IcingaMySQL->create_magic_cookie(\%Options);
	
	} else {
			warn "$0 :: no incident(OK) \n";
	}
}

exit 0;

#===============================================================================
# END
#===============================================================================

__END__


=head1 NAME

servicenow_notification.pl - nagios/icinga check for graylog hits

=head1 SYNOPSIS

./servicenow_notification.pl 

=head1 DESCRIPTION

This description does not exist yet, it
was made for the sole purpose of demonstration.

=head1 LICENSE

This is released under the GPL3.

=head1 AUTHOR

Denis Immoos <denisimmoos@gmail.com>,
Senior Linux System Administrator (LPIC3)

