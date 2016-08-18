package IcingaMySQL;

#===============================================================================
#
#         FILE: MySql.pm
#      PACKAGE: IcingaMySQL
#
#  DESCRIPTION: IcingaMySQL interface for Messages
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Denis Immoos (<denis.immoos@soprasteria.com>)
#    AUTHORREF: Senior Linux System Administrator (LPIC3)
# ORGANIZATION: Sopra Steria Switzerland
#      VERSION: 1.0
#      CREATED: 08/15/2016 01:06:16 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

sub new
{
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
} 

sub error {
	my $caller = shift;
	my $msg = shift || $caller;
	die( "ERROR($caller): $msg" );
}

sub verbose {
	my $caller = shift;
	my $msg = shift || $caller;
	print( "INFO($caller): $msg" . "\n" );
}

use DBI;

sub check_ack {
	my $self        = shift;
	my $ref_Options = shift;
	my %Options = %{ $ref_Options };
	my $caller = (caller(0))[3];
	my $sql;

	sleep $Options{'ack_sleep_time'};
	
	$sql= "SELECT comment_data FROM icinga_comments WHERE 
		         object_id = (
				    SELECT object_id FROM icinga_objects
				    WHERE
					name1 = '$Options{'ENV'}{'HOSTDISPLAYNAME'}'
					AND
     				name2 = '$Options{'ENV'}{'SERVICEDISPLAYNAME'}'
					)
		  AND entry_type = 4 
		  ORDER BY entry_time ASC LIMIT 1";


	my $dbh = DBI->connect("dbi:mysql:database=$Options{'mysql_db'};host=$Options{'mysql_host'};port=$Options{'mysql_port'}", $Options{'mysql_user'}, $Options{'mysql_passwd'} )
	          or die( $DBI::errstr . "\n");

     my $sth = $dbh->prepare($sql);
	 my $status = $sth->execute;

	# save status for later use
	while ( my $row = $sth->fetchrow_hashref ) {
		   $Options{'check_ack'} = $row;
	}

	$dbh->disconnect;
	return %Options;
}

sub delete_magic_cookie {

	my $self        = shift;
	my $ref_Options = shift;
	my %Options = %{ $ref_Options };
	my $caller = (caller(0))[3];
	my $sql;


	# $Options{'get_json_result'}{'sys_id'}
	if ( $Options{'get_json_result'}{'sys_id'} ){
	    $sql= "DELETE FROM `icinga`.`icinga_comments` WHERE `icinga_comments`.`comment_data` LIKE '%$Options{'get_json_result'}{'sys_id'}%'";
	}
	
	# $Options{'IcingaMySQL'}{'sys_id'}
	if ( $Options{'IcingaMySQL'}{'sys_id'} ){
	    $sql= "DELETE FROM `icinga`.`icinga_comments` WHERE `icinga_comments`.`comment_data` LIKE '%$Options{'IcingaMySQL'}{'sys_id'}%'";
	}

	my $dbh = DBI->connect("dbi:mysql:database=$Options{'mysql_db'};host=$Options{'mysql_host'};port=$Options{'mysql_port'}", $Options{'mysql_user'}, $Options{'mysql_passwd'} )
	          or die( $DBI::errstr . "\n");

    my $sth = $dbh->prepare($sql);
	my $status = $sth->execute;

	# save status for later use
	$Options{'delete_magic_cookie'}{'status'} = $status;

	$dbh->disconnect;
	return %Options;
}

sub create_magic_cookie {

	my $self        = shift;
	my $ref_Options = shift;
	my %Options = %{ $ref_Options };
	my $caller = (caller(0))[3];
	my $sql;

	$sql= "
		SELECT endpoint_object_id, object_id FROM `icinga_notifications` 
		WHERE 
		object_id = (
	    SELECT object_id FROM icinga_objects
	    WHERE
		name1 = '$Options{'ENV'}{'HOSTDISPLAYNAME'}'
		AND
		name2 = '$Options{'ENV'}{'SERVICEDISPLAYNAME'}'
        )
		ORDER by end_time DESC
		LIMIT 1
		";

	my $dbh = DBI->connect("dbi:mysql:database=$Options{'mysql_db'};host=$Options{'mysql_host'};port=$Options{'mysql_port'}", $Options{'mysql_user'}, $Options{'mysql_passwd'} )
	          or die( $DBI::errstr . "\n");

    my $sth = $dbh->prepare($sql);
	   $sth->execute;

	while ( my $row = $sth->fetchrow_hashref ) {
		   $Options{'IcingaMySQL'} = $row;
	}
    
	# 2016-08-16 14:05:40
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	# 4 digits
	$year += 1900;
	$mon  = sprintf("%02d", $mon );
	$mday = sprintf("%02d", $mday );
	$hour = sprintf("%02d", $hour );
	$min  = sprintf("%02d", $min );
	$sec  = sprintf("%02d", $sec );
	$Options{'create_magic_cookie'}{'time'} = "$year-$mon-$mday $hour:$min:$sec";

	if ( $Options{'IcingaMySQL'}{'endpoint_object_id'} and $Options{'IcingaMySQL'}{'object_id'} ) {

		# INSERT

		$sql = "INSERT INTO icinga.icinga_comments ( 
			   `comment_id`,           
			   `instance_id`,         
			   `entry_time`, 
			   `entry_time_usec`, 
			   `comment_type`, 
			   `entry_type`, 
			   `object_id`, 
			   `comment_time`, 
			   `internal_comment_id`, 
			   `author_name`, 
			   `comment_data`, 
			   `is_persistent`, 
			   `comment_source`, 
			   `expires`, 
			   `expiration_time`, 
			   `endpoint_object_id`, 
			   `name`) 
			   VALUES ( 
			          NULL, 
					  '1', 
					  '$Options{'create_magic_cookie'}{'time'}',
					  '',
					  '1',
					  '1', 
					  '$Options{'IcingaMySQL'}{'object_id'}', 
					  '$Options{'create_magic_cookie'}{'time'}',
					  '13', 
					  'icinga', 
					  'number:$Options{'post_incident'}{'number'},sys_id:$Options{'post_incident'}{'sys_id'}', 
					  '1', 
					  '1', 
					  '0', 
					  '0000-00-00 00:00:00', 
					  '$Options{'IcingaMySQL'}{'endpoint_object_id'}', 
					  '$Options{'ENV'}{'HOSTDISPLAYNAME'}!$Options{'ENV'}{'SERVICEDISPLAYNAME'}!servicenow!$Options{'create_magic_cookie'}{'time'}'
					  )
		";

       $sth = $dbh->prepare($sql);
	   $sth->execute;

	} else {
		die "$caller : SQL failed \n";
	}

	$dbh->disconnect;
	return %Options;
}



sub get_magic_cookie {

	my $self        = shift;
	my $ref_Options = shift;
	my %Options = %{ $ref_Options };
	my $caller = (caller(0))[3];

	my $sql = "SELECT comment_data FROM `icinga_comments` 
	           WHERE 
	           endpoint_object_id = ( 
							  SELECT endpoint_object_id FROM icinga_notifications 
							  WHERE 
							  object_id = (
											SELECT object_id FROM icinga_objects
											WHERE 
											name1 = '$Options{'ENV'}{'HOSTDISPLAYNAME'}'
											AND
											name2 = '$Options{'ENV'}{'SERVICEDISPLAYNAME'}' 
										   ) ORDER by end_time DESC LIMIT 1
							 ) 
				AND
				comment_data LIKE '%number:%INC%sys_id:%'
				AND 
				name LIKE '%$Options{'ENV'}{'SERVICEDISPLAYNAME'}%'
				";


	my $dbh = DBI->connect("dbi:mysql:database=$Options{'mysql_db'};host=$Options{'mysql_host'};port=$Options{'mysql_port'}", $Options{'mysql_user'}, $Options{'mysql_passwd'} )
	          or die( $DBI::errstr . "\n");

    my $sth = $dbh->prepare($sql);
	   $sth->execute;

	while ( my $row = $sth->fetchrow_hashref ) {
		   $Options{'IcingaMySQL'} = $row;
	}

	# get tes sys_id
	if ($Options{'IcingaMySQL'}{'comment_data'}) {
		 my @comment_data = split(/\,/,$Options{'IcingaMySQL'}{'comment_data'} );
		 $Options{'IcingaMySQL'}{'number'} = $comment_data[0];
		 $Options{'IcingaMySQL'}{'number'} =~ s/number://g;
		 $Options{'IcingaMySQL'}{'number'} =~ s/\ +//g;
		 chomp($Options{'IcingaMySQL'}{'number'});

		 $Options{'IcingaMySQL'}{'sys_id'} = $comment_data[1];
		 $Options{'IcingaMySQL'}{'sys_id'} =~ s/sys_id://g;
		 $Options{'IcingaMySQL'}{'sys_id'} =~ s/\ +//g;
		 chomp($Options{'IcingaMySQL'}{'sys_id'});
	}

	$dbh->disconnect;
	
	return %Options;
}


1;



__END__

=head1 NAME

IcingaMySQL - IcingaMySQL interface for Messages 

=head1 SYNOPSIS

use IcingaMySQL;

my $object = IcingaMySQL->new();

=head1 DESCRIPTION

This description does not exist yet, it
was made for the sole purpose of demonstration.

=head1 LICENSE

This is released under the GPL3.

=head1 AUTHOR

Denis Immoos - <denis.immoos@soprasteria.com>, Senior Linux System Administrator (LPIC3)

=cut


