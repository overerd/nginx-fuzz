package Fuzz::Core;

use warnings;
use strict;

use Fuzz::Request;
use Fuzz::RequestLight;
use Fuzz::MIME;

sub RequestHandler
{
	my ($nginx, $fdata, $fconfig) = @_;

	my %handlers;

	if($$fdata{'ServerInsecureMode'}) {
		%handlers = (
			'request' => \Fuzz::Request::RequestHandler,
			'add' => \Fuzz::Request::RequestHandler,
			'add-absolute' => \Fuzz::Request::RequestHandler,
			'reverse' => \Fuzz::Request::RequestHandler
		);
	} else {
		%handlers = (
			'request' => \Fuzz::RequestLight::RequestHandler,
			'add' => \Fuzz::RequestLight::RequestHandler,
			'add-absolute' => \Fuzz::RequestLight::RequestHandler,
			'reverse' => \Fuzz::RequestLight::RequestHandler
		);
	}

	if($$fdata{'ServerStartTime'})
	{
		return $handlers{'request'}($nginx, $fdata);
	}

	$$fdata{'conf'} = $fconfig;

	$$fdata{'rehashes'} = {};
	$$fdata{'rehashesList'} = ();

	$$fconfig{'dir'} .= '/' if !$$fconfig{'dir'} =~ /\/$/;

	$$fdata{'SessionExpire'}	=$$fconfig{'session_expire'} // 600;
	$$fdata{'SessionKey'}		=$$fconfig{'session_key'} // 'key';

	$$fdata{'CookiesExpire'}	=$$fconfig{'cookie_expire'} // 100;

	if($$fconfig{'SecuredConnection'})
	{
		$$fdata{'SecuredConnection'} = 1;
	}

	if($$fconfig{'default_mime'})
	{
		$$fdata{'mime_default'} = $$fconfig{'default_mime'};
	}
	else
	{
		$$fdata{'mime_default'} = Fuzz::MIME::ExtensionToMIMEString('raw');
	}

	$$fdata{'escaped'}		=$$fconfig{'escaped'} // 1;
	$$fdata{'escaped_chars'}	=$$fconfig{'escaped_chars'} // '\x22\x26\x3c\x3e\xa0\x2f';
	$$fdata{'template_clearable'}	=$$fconfig{'template_clearable'} // 1;

	$$fdata{'dir'}			=$$fconfig{'dir'};
	$$fdata{'dir_upload'}		=$$fconfig{'dir_upload'} // ($$fconfig{'dir'} . 'uploads/');
	$$fdata{'dir_templates'}	=$$fconfig{'dir_templates'} // ($$fconfig{'dir'} . 'templates/');

	$$fdata{'dir'}			.='/' if!($$fconfig{'dir'} =~ /\/$/);
	$$fdata{'dir_upload'}		.='/' if!($$fconfig{'dir_upload'} =~ /\/$/);
	$$fdata{'dir_templates'}	.='/' if!($$fconfig{'dir_templates'} =~ /\/$/);

	$$fdata{'redis_conf'}		=$$fconfig{'redis'};
	$$fdata{'redis_db'}		=$$fconfig{'redis_db'} // 0;

	for my $r(keys %{$$fconfig{'map'}})
	{
		$handlers{'add'}($fdata, $r, $$fconfig{'map'}{$r});
	}

	for my $r(keys %{$$fconfig{'amap'}})
	{
		$handlers{'add-absolute'}($fdata, $r, $$fconfig{'amap'}{$r});
	}

	$handlers{'reverse'}($fdata);

	$$fdata{'ServerStartTime'} = time;

	return $handlers{'request'}($nginx, $fdata);
}

sub ResetData
{
	my $fdata = shift;

	delete $$fdata{'conf'};

	sub PurgeNode
	{
		my $node = shift;
		my $i = 0;

		if(ref($node) eq 'HASH')
		{
			for my $r(keys %$node)
			{
				PurgeNode($$node{$r});
				delete $$node{$r};
			}
		}
		else
		{
			if(ref($node) eq 'ARRAY')
			{
				for ($i = 0; $i < scalar( @$node ); $i++)
				{
					PurgeNode($$node[$i]);
					delete $$node[$i];
				}
			}
		}
	}

	PurgeNode($fdata);
}

1;
__END__
