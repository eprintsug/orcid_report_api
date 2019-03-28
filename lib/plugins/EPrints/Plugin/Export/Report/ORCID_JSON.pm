package EPrints::Plugin::Export::Report::ORCID_JSON;

use Data::Dumper;
use JSON;
use utf8;
use EPrints::Plugin::Export::Report;
use Encode;
@ISA = ( "EPrints::Plugin::Export::Report" );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	$self->{name} = "ORCID JSON";
	$self->{suffix} = ".js";
	#	$self->{mimetype} = "application/json; charset=utf-8";
	$self->{mimetype} = "text/json; charset=utf-8";
	$self->{accept} = [ 'report/generic' ];
	$self->{advertise} = 1;
	$self->{arguments}->{json} = undef;
	$self->{arguments}->{jsonp} = undef;
	$self->{arguments}->{callback} = undef;
	$self->{arguments}->{hide_volatile} = 1;


	return $self;
}

sub _header
{
        my( $self, %opts ) = @_;

        my $jsonp = $opts{json} || $opts{jsonp} || $opts{callback};
        if( EPrints::Utils::is_set( $jsonp ) )
        {
                $jsonp =~ s/[^=A-Za-z0-9_]//g;
                return "$jsonp(";
        }

        return "";
}

sub _footer
{
        my( $self, %opts ) = @_;

        my $jsonp = $opts{json} || $opts{jsonp} || $opts{callback};
        if( EPrints::Utils::is_set( $jsonp ) )
        {
                return ");\n";
        }
        return "";
}

sub output_list
{
        my( $plugin, %opts ) = @_;     

	$plugin->get_export_fields( %opts ); #get export fields based on user requirements or plugin defaults
	my $repo = $plugin->repository;

	my $ds = $opts{dataset};
        $plugin->{dataset} = $ds;

	my $r = [];
        my $part;
        $part = $plugin->_header(%opts)."[\n";
        if( defined $opts{fh} )
        {
		print {$opts{fh}} $part;
        }
        else
        {
                push @{$r}, $part;
        }

      	my $key_type = $opts{key_type}; # either userid or orcid...possibly other crap

        $opts{json_indent} = 1;
        my $first = 1;
	my $user_eprints = $opts{list};
	foreach my $key ( keys %{$user_eprints} )
	{
		my $list = $user_eprints->{$key}->{eprints};	
		my $json_data = {};
		
		#we have a user
		if(EPrints::Utils::is_set($user_eprints->{$key}->{user})){
			my $user = $user_eprints->{$key}->{user};
			$json_data->{repositoryId} = [$user->id];
			$json_data->{orcid} = [$user->get_value( "orcid" )];
			$json_data->{names} = [EPrints::Utils::tree_to_utf8($repo->render_name($user->value("name"),"givenfirst"))];
			$json_data->{emails} = [$user->value("email")];
			$json_data->{orcidIsAuthenticated} = 'true';
			$json_data->{typeOfPerson} = [$user->get_type]
		#we don't have a user but we do have an orcid
		}elsif($key_type eq "orcid"){
			#user not available... we may have orcid
			$json_data->{orcid} = [$key];
			$json_data->{orcidIsAuthenticated} = 'false';
			$json_data->{typeOfPerson} = ['external_creator']
		}
		$json_data->{publishedWorks} = [];
		#no repository id? perhaps no linked user... so lets have a look in the eprints.creators
		if(!EPrints::Utils::is_set($json_data->{repositoryId})){
			$json_data->{repositoryId} = [];
		}
		#print STDERR "list....$list\n";
		#eprint data....
		foreach my $e ( @{$user_eprints->{$key}->{eprints}} )
		{
			my $pub_work = {};
			if(!EPrints::Utils::is_set($json_data->{repositoryId})){

				for my $creator (@{$e->value("creators")}){
					if(EPrints::Utils::is_set($creator->{id}) && 
						grep $_ eq $creator->{orcid}, @{$json_data->{orcid}}){
						next if grep $_ eq $creator->{id}, @{$json_data->{repositoryId}};

						#TODO make "id" a configurable item
						push @{$json_data->{repositoryId}}, $creator->{id};
					}
				}
			}
			if( $first ) { $first = 0; } else { $part = ",\n"; }

			#TODO this map should be configurable
			my $pw_map = { title => "title",
				    id_number => "doi", 
				    issn => "issn",
				    eissn => "issn", 
				    isbn => "isbn", 
				    pmid => "pubmedID", 
				    pmcid => "pubmedCentralId"
			};

			while(my($ep_field,$pw_field) = each(%{$pw_map})){
				$pub_work->{$pw_field} = [] if !EPrints::Utils::is_set($pub_work->{$pw_field});
				push @{$pub_work->{$pw_field}}, $e->value($ep_field) if $e->exists_and_set($ep_field); 
			}
			#dirty compromise regarding possilbe non-persistant local reference to record
			$pub_work->{localId} = [$e->url];

			push @{$json_data->{publishedWorks}}, $pub_work; 
		}

		#print STDERR "json_data.....$json_data\n";
		#		my $json_string = encode_json( $json_data );

		my $json_obj = JSON->new->allow_nonref;

            	my $json_string = $json_obj->pretty->encode($json_data);	
		#	my $json_string = JSON->new->utf8->encode($json_data);
		#my $json_string = EPrints::Utils::js_string( $json_data );
		#print STDERR "json_string....$json_string\n";
		if( defined $opts{fh} )
		{
                       	print {$opts{fh}} $json_string;
                }
                else
                {
                      	push @{$r}, $json_string;
  		}
        }

        $part= "\n]\n\n".$plugin->_footer(%opts);
        if( defined $opts{fh} )
        {
                print {$opts{fh}} $part;
        }
        else
        {
                push @{$r}, $part;
        }


        if( defined $opts{fh} )
        {
                return;
        }

        return join( '', @{$r} );
}

sub _epdata_to_json
{
	my( $self, $eprint, %opts ) = @_;

	my $repo = $self->repository;


	my $filtered_eprint_data = {};
	foreach my $fieldname ( @{$self->{exportfields}} )
	{
		print STDERR "fieldname.....$fieldname\n";
		my @fnames = split( /\./, $fieldname );
		if( scalar( @fnames > 1 ) ) #a field of another dataset, e.g. documents.content
		{
=comment
			my $field = $self->{dataset}->get_field( $fnames[0] ); #first get the field
			if( $field->is_type( "subobject", "itemref" ) ) #if thee field belongs to another dataset
			{
				my $subsubdata = $subdata->{$fnames[0]} || []; #create an array for the sub ojects
				my $dataobjs= $eprint->value( $fnames[0] ); #get the dataobjects this field represents
				for (my $i=0; $i < scalar( @{$dataobjs} ); $i++)
				{
					my $obj = @{$dataobjs}[$i]; #get the value from the dataobject			
					my $value = $obj->value( $fnames[1] );
					next if !EPrints::Utils::is_set( $value );

					my $subsubsubdata = $subdata->{$fnames[0]}[$i] || {};
					$subsubsubdata->{$fnames[1]} = $value;		

					$subdata->{$fnames[0]}[$i] = $subsubsubdata;					
				}                                   
		       }
=cut
		}
		else
		{
			my $field = $self->{dataset}->get_field( $fieldname );
			next if !$field->get_property( "export_as_xml" );
			next if defined $field->{sub_name};
			my $value = $field->get_value( $eprint );				
			print STDERR "value: ".$value."\n";


			if( exists $self->{report}->{export_conf} && exists $repo->config( $self->{report}->{export_conf}, "custom_export" )->{$field->get_name} )
			{
				print STDERR "csutom_export...\n";
				$value = $repo->config( $self->{report}->{export_conf}, "custom_export" )->{$field->get_name}->( $eprint, $self->{report} );
			}
			if( defined $field->{virtual} )
			{
				$value = EPrints::Utils::tree_to_utf8( $eprint->render_value( $field->get_name ) );
			}
			next if !EPrints::Utils::is_set( $value );
			$filtered_eprint_data->{$field->get_name} = $value;
		}
	}

	return $filtered_eprint_data;
}
=comment
sub _epdata_to_json
{
        my( $self, $epdata, $depth, $in_hash, %opts ) = @_;

	my $repo = $self->repository;

        my $pad = "  " x $depth;
        my $pre_pad = $in_hash ? "" : $pad;


        if( !ref( $epdata ) )
        {

                if( !defined $epdata )
                {
                        return "null"; # part of a compound field
                }

		if( $epdata =~ /^-?[0-9]*\.?[0-9]+(?:e[-+]?[0-9]+)?$/i )
		{
		        return $pre_pad . ($epdata + 0);
		}
		else
		{
		        return $pre_pad . EPrints::Utils::js_string( $epdata );
		}
        }
        elsif( ref( $epdata ) eq "ARRAY" )
        {
                return "$pre_pad\[\n" . join(",\n", grep { length $_ } map {
                        $self->_epdata_to_json( $_, $depth + 1, 0, %opts )
                } @$epdata ) . "\n$pad\]";
        }
        elsif( ref( $epdata ) eq "HASH" )
        {
                return "$pre_pad\{\n" . join(",\n", map {
                        $pad . "  \"" . $_ . "\": " . $self->_epdata_to_json( $epdata->{$_}, $depth + 1, 1, %opts )
                } keys %$epdata) . "\n$pad\}";
        }
        elsif( $epdata->isa( "EPrints::DataObj" ) )
        {
                my $subdata = {};

                return "" if(
                        $opts{hide_volatile} &&
                        $epdata->isa( "EPrints::DataObj::Document" ) &&
                        $epdata->has_relation( undef, "isVolatileVersionOf" )
                  );

                foreach my $fieldname ( @{$self->{exportfields}} )
                {
			print STDERR "fieldname.....$fieldname\n";
			my @fnames = split( /\./, $fieldname );
                        if( scalar( @fnames > 1 ) ) #a field of another dataset, e.g. documents.content
                        {
				my $field = $self->{dataset}->get_field( $fnames[0] ); #first get the field
                                if( $field->is_type( "subobject", "itemref" ) ) #if thee field belongs to another dataset
                                {
					my $subsubdata = $subdata->{$fnames[0]} || []; #create an array for the sub ojects
                                	my $dataobjs= $epdata->value( $fnames[0] ); #get the dataobjects this field represents
					for (my $i=0; $i < scalar( @{$dataobjs} ); $i++)
					{
						my $obj = @{$dataobjs}[$i]; #get the value from the dataobject			
						my $value = $obj->value( $fnames[1] );
						next if !EPrints::Utils::is_set( $value );

						my $subsubsubdata = $subdata->{$fnames[0]}[$i] || {};
						$subsubsubdata->{$fnames[1]} = $value;		

						$subdata->{$fnames[0]}[$i] = $subsubsubdata;					
                                        }                                   
                               }
			}
			else
			{
				my $field = $self->{dataset}->get_field( $fieldname );
	                        next if !$field->get_property( "export_as_xml" );
        	                next if defined $field->{sub_name};
				my $value = $field->get_value( $epdata );				
				if( exists $self->{report}->{export_conf} && exists $repo->config( $self->{report}->{export_conf}, "custom_export" )->{$field->get_name} )
        	                {
					$value = $repo->config( $self->{report}->{export_conf}, "custom_export" )->{$field->get_name}->( $epdata, $self->{report} );
				}
				if( defined $field->{virtual} )
				{
					$value = EPrints::Utils::tree_to_utf8( $epdata->render_value( $field->get_name ) );
				}
		                next if !EPrints::Utils::is_set( $value );
        	                $subdata->{$field->get_name} = $value;
			}
                }
                $subdata->{uri} = $epdata->uri;

                return $self->_epdata_to_json( $subdata, $depth + 1, 0, %opts );
        }
}
=cut

sub escape_value
{
	my( $plugin, $value ) = @_;

	return '""' unless( defined EPrints::Utils::is_set( $value ) );

	# strips any kind of double-quotes:
	$value =~ s/\x93|\x94|"/'/g;
	# and control-characters
	$value =~ s/\n|\r|\t//g;

	# if value is a pure number, then add ="$value" so that Excel stops the auto-formatting (it'd turn 123456 into 1.23e+6)
	if( $value =~ /^[0-9\-]+$/ )
	{
		return "=\"$value\"";
	}

	# only escapes row with spaces and commas
	if( $value =~ /,| / )
	{
		return "\"$value\"";
	}

	return $value;
}


1;
