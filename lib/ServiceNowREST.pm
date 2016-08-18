package ServiceNowREST;

#===============================================================================
#
#         FILE: ServiceNowREST.pm
#      PACKAGE: ServiceNowREST
#
#  DESCRIPTION: ServiceNowREST interface
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Denis Immoos (<denis.immoos@soprasteria.com>)
#    AUTHORREF: Senior Linux System Administrator (LPIC3)
# ORGANIZATION: Sopra Steria Switzerland
#      VERSION: 1.0
#      CREATED: 08/15/2016 04:26:07 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

use MIME::Base64;
use JSON;
use REST::Client;


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

#
# DEFAULTS
#
our %state = (
	OK       => 6, # resolved
	CRITICAL => 2,
	WARNING  => 2,
	UNKNOWN  => 2,
	ACK => 4, #awaiting user info
);

our %impact = (
	OK       => 3,
	CRITICAL => 1,
	WARNING  => 2,
	UNKNOWN  => 1,
);

our %urgency = (
	OK       => 3,
	CRITICAL => 1,
	WARNING  => 2,
	UNKNOWN  => 1,
);

our %priority = (
	OK       => 1,
	CRITICAL => 1,
	WARNING  => 1,
	UNKNOWN  => 1,
);




#
# get_json_result
#


sub get_json_result {

    my $self        = shift;
    my $ref_Options = shift;
    my %Options = %{ $ref_Options };
    my $caller = (caller(0))[3];
    my %json_result = ();

    if ($Options{'IcingaMySQL'}{'sys_id'}) {

		#http://search.cpan.org/~mcrawfor/REST-Client/lib/REST/Client.pm
		# Example install using cpanm:
		#   sudo cpanm -i REST::Client
		my $rest_client = REST::Client->new( host => $Options{'servicenow_url'}) or &error;
		my $encoded_auth = encode_base64("$Options{'servicenow_username'}:$Options{'servicenow_password'}", '') or &error;

        $rest_client->GET(  "/api/now/table/incident?sysparm_limit=1&sys_id=$Options{'IcingaMySQL'}{'sys_id'}", {'Authorization' => "Basic $encoded_auth", 'Accept' => 'application/json'});


        # JSON
		my $json = JSON->new;
        my $json_result = $json->decode($rest_client->responseContent());

        %json_result = %{ $json_result } ;


		use Data::Dumper;

		# if there are results
		if (@{  $json_result{'result'} }){
			# its a bloody array
			%json_result = %{ (@{ $json_result{'result'}} )[0] };

			  foreach my $key (keys(%json_result)) {
						  $Options{'get_json_result'}{$key} = $json_result{$key};
			  }
        }

    }
      return %Options;	
}

#
# post_incident - Create an incident
#


sub post_incident {
	my $self        = shift;
	my $ref_Options = shift;
	my %Options = %{ $ref_Options };
	my $caller = (caller(0))[3];

	# comes from service
	$Options{'ENV'}{'COMPANY'} = 'BOS Steria';
	$Options{'ENV'}{'ASSIGNMENT_GROUP'} = 'BOS Infrastructure';

	my %template = (
	
		# on create the state is new
		state => 1,
		company => $Options{'ENV'}{'COMPANY'},
		assignment_group => $Options{'ENV'}{'ASSIGNMENT_GROUP'}, 
		caller_id => 'fwel',  
		impact => $impact{$Options{'ENV'}{'SERVICESTATE'}},  
		urgency => $urgency{$Options{'ENV'}{'SERVICESTATE'}},  
		priority => $priority{$Options{'ENV'}{'SERVICESTATE'}},  
		short_description => $Options{'ENV'}{'SERVICESTATE'} . " :: " . $Options{'ENV'}{'HOSTDISPLAYNAME'} . " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'} ,  
		description =>  "\n"  . "HOSTADDRESS: " . $Options{'ENV'}{'HOSTADDRESS'}  
					    . "\n" .  "LONGDATETIME: "  . $Options{'ENV'}{'LONGDATETIME'}  
					    . "\n" .  "SERVICEOUTPUT: " 
		                . "\n" .  $Options{'ENV'}{'SERVICEOUTPUT'}
						. "\n",  
		category => 'Failure',  
		subcategory => 'Malfunction',  
		u_external_reference => "$Options{'icingaweb2_url'}/monitoring/service/show?host=$Options{'ENV'}{'HOSTDISPLAYNAME'}&service=$Options{'ENV'}{'SERVICEDISPLAYNAME'}",
	);



        # 
		# append ACK
		#

		if ($Options{'check_ack'}{'comment_data'} ) {
			$template{'state'} =  $state{'ACK'};
			$template{'short_description'} = "ACK :: " . $Options{'ENV'}{'SERVICESTATE'} . " :: " . $Options{'ENV'}{'HOSTDISPLAYNAME'} . " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'};
		    $template{'description'} = 
			             "\n"  . "ACK: " . $Options{'check_ack'}{'comment_data'}
			            . "\n\n"  . "HOSTADDRESS: " . $Options{'ENV'}{'HOSTADDRESS'}  
					    . "\n" .  "LONGDATETIME: "  . $Options{'ENV'}{'LONGDATETIME'}  
					    . "\n" .  "SERVICEOUTPUT: " 
		                . "\n" .  $Options{'ENV'}{'SERVICEOUTPUT'}
						. "\n";  
		}

	
		my $rest_client = REST::Client->new( host => $Options{'servicenow_url'}) or &error;
		my $encoded_auth = encode_base64("$Options{'servicenow_username'}:$Options{'servicenow_password'}", '') or &error;

		my $json = JSON->new;
        my $json_request_body = $json->encode(\%template);


		my $json_result = $rest_client->POST("/api/now/table/incident", $json_request_body, {'Authorization' => "Basic $encoded_auth", 'Content-Type' => 'application/json', 'Accept' => 'application/json'}) or &error; 


		# get the resule
		$json_result = $json_result->responseContent;

		
		# umwursteln in HASH
		$json_result = $json->decode($json_result);

		my %json_result = %{ $json_result };

		# collect return values
		foreach my $key (keys %{ $json_result{'result'} } ) {
			$Options{'post_incident'}{$key} = $json_result{'result'}{$key};
		}

        return %Options;
}


#
# update_incident
#

sub update_incident {

    my $self        = shift;
    my $ref_Options = shift;
    my %Options = %{ $ref_Options };
    my $caller = (caller(0))[3];
    my %json_result = ();

	my %template = (
	
		# on create the state is new
		state      => $state{$Options{'ENV'}{'SERVICESTATE'}},
		impact     => $impact{$Options{'ENV'}{'SERVICESTATE'}},  
		urgency    => $urgency{$Options{'ENV'}{'SERVICESTATE'}},  
		priority   => $priority{$Options{'ENV'}{'SERVICESTATE'}},  
		short_description => $Options{'ENV'}{'SERVICESTATE'} . " :: " . $Options{'ENV'}{'HOSTDISPLAYNAME'} . " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'} ,  
		description =>    "\n"  . "HOSTADDRESS: " . $Options{'ENV'}{'HOSTADDRESS'}  
					    . "\n" .  "LONGDATETIME: "  . $Options{'ENV'}{'LONGDATETIME'}  
					    . "\n" .  "SERVICEOUTPUT: " 
		                . "\n" .  $Options{'ENV'}{'SERVICEOUTPUT'}
						. "\n",  
		u_external_reference => "$Options{'icingaweb2_url'}/monitoring/service/show?host=$Options{'ENV'}{'HOSTDISPLAYNAME'}&service=$Options{'ENV'}{'SERVICEDISPLAYNAME'}",
	);
	

	# 
	# append ACK
	#

	if ($Options{'check_ack'}{'comment_data'} ) {
		$template{'state'} =  $state{'ACK'};
		$template{'short_description'} = "ACK :: " . $Options{'ENV'}{'SERVICESTATE'} . " :: " . $Options{'ENV'}{'HOSTDISPLAYNAME'} . " :: " . $Options{'ENV'}{'SERVICEDISPLAYNAME'};
		$template{'description'} = 
					 "\n"  . "ACK: " . $Options{'check_ack'}{'comment_data'}
					. "\n\n"  . "HOSTADDRESS: " . $Options{'ENV'}{'HOSTADDRESS'}  
					. "\n" .  "LONGDATETIME: "  . $Options{'ENV'}{'LONGDATETIME'}  
					. "\n" .  "SERVICEOUTPUT: " 
					. "\n" .  $Options{'ENV'}{'SERVICEOUTPUT'}
					. "\n";  
	}

	my $rest_client = REST::Client->new( host => $Options{'servicenow_url'}) or &error;
	my $encoded_auth = encode_base64("$Options{'servicenow_username'}:$Options{'servicenow_password'}", '') or &error;

	my $json = JSON->new;
	my $json_request_body = $json->encode(\%template);

	my $json_result = $rest_client->PATCH("/api/now/table/incident/$Options{'get_json_result'}{'sys_id'}", 
	   $json_request_body, {'Authorization' => "Basic $encoded_auth", 'Content-Type' => 'application/json', 'Accept' => 'application/json'}); 
													   
    # get the resule
	$json_result = $json_result->responseContent;
	
	#
	# umwursteln in HASH
	#
	$json_result = $json->decode($json_result);
	
	# result hash
	%json_result = %{ $json_result };

	# collect return values
	foreach my $key (keys %{ $json_result{'result'} } ) {
	    $Options{'update_incident'}{$key} = $json_result{'result'}{$key};
	}

    return %Options;
}

1;

__END__

=head1 NAME

ServiceNowREST - ServiceNowREST interface 

=head1 SYNOPSIS

use ServiceNowREST;

my $object = ServiceNowREST->new();

=head1 DESCRIPTION

This description does not exist yet, it
was made for the sole purpose of demonstration.

=head1 LICENSE

This is released under the GPL3.

=head1 AUTHOR

Denis Immoos - <denis.immoos@soprasteria.com>, Senior Linux System Administrator (LPIC3)

=cut


