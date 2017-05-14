package Fuzz::Request;

use warnings;
use strict;

use URI::Escape;
use Fuzz::Cookies;
use Fuzz::Session;
use Fuzz::Template;
use Fuzz::MIME;

sub RequestHandler
{
	my $nginx = shift;
	my $fdata = shift;

	for my $q(@{$$fdata{'rehashesList'}})
	{
		my @request_args = ($nginx->uri =~ /$q/);

		if(@request_args)
		{
			my $customRequest;
			my $cookies = Fuzz::Cookies::Read($nginx->header_in('Cookie'));

			$$customRequest{'nginx'}	=$nginx;
			$$customRequest{'ip'}		=$nginx->remote_addr;
			$$customRequest{'dir'}		=$$fdata{'dir'};
			$$customRequest{'method'}	=$nginx->request_method;
			$$customRequest{'cookies'}	=Fuzz::Cookies::Read($nginx->header_in('Cookie'));

			if($$fdata{'SessionEnabled'}) {
				$$customRequest{'sid'}		=Fuzz::Session::new($fdata, $$customRequest{'ip'}, $$customRequest{'cookies'}{$$fdata{'SessionKey'}});
				$$customRequest{'session'}	=Fuzz::Session::Load($fdata, $$customRequest{'sid'}) // ();
			}

			$$customRequest{'template_escaped'} = $$fdata{'escaped'};

			my %get;

			for(split '&', $nginx->args)
			{
				/(\w+(\[\])?)=([^&]*)/;
				$2
					? (
						exists $get{$1}
							? ( push $get{$1}, $3 )
							: ( $get{$1} = [$3] )
					)
					: ( $get{$1} = $3 );
			}

			my @uri_args = map { /\/?([^\/]+)/g } $nginx->uri;

			shift @uri_args;

			$$customRequest{'get'}				=\%get;
			$$customRequest{'arguments'}			=\@uri_args;

			$$customRequest{'via'}				=$nginx->header_in('Via');
			$$customRequest{'UserAgent'}			=$nginx->header_in('User-Agent');
			$$customRequest{'referer'}			=$nginx->header_in('Referer');
			$$customRequest{'host'}				=$nginx->header_in('Host');
			$$customRequest{'xff'}				=$nginx->header_in('X-Forwarded-For');
			$$customRequest{'xrw'}				=$nginx->header_in('X-Requested-With');

			$$customRequest{'response'} = {};

			my ($request_type, $request_output);

			if(ref($$fdata{'rehashes'}{$q}) eq 'CODE')
			{
				$$fdata{'rehashes'}{$q}($customRequest, @request_args);

				extendResponse($nginx, $$customRequest{'response'});

				Fuzz::Session::Update(
					$fdata,
					$$customRequest{'sid'},
					$$customRequest{'session'}
				) if $$fdata{'SessionEnabled'};

				Fuzz::Cookies::Update(
					$nginx,
					$fdata,
					$cookies,
					$$customRequest{'cookies'}
				);

				Fuzz::Cookies::Set(
					$nginx,
					$$fdata{'SessionKey'},
					$$customRequest{'sid'},
					$$fdata{'SessionExpire'}
				);

				return ($$customRequest{'status'} == 301 ? 301 : 302) if $$customRequest{'response'}{'Location'};

				if(exists $$customRequest{'template'})
				{
					$request_type = $$customRequest{'type'} // Fuzz::MIME::ExtensionToMIMEString($$customRequest{'template'});
					$request_output = Fuzz::Template::Render(
								$fdata,
								$$customRequest{'template'},
								$$customRequest{'template_args'},
								$$customRequest{'template_escaped'},
								$$fdata{'template_clearable'}
							);

					$nginx->send_http_header($request_type);
					$nginx->print($request_output);
				}
				else
				{
					if(!$$customRequest{'raw'})
					{
						$request_type = $$customRequest{'type'} // $$fdata{'mime_default'};

						$nginx->send_http_header($request_type);
					}
				}

				return $$customRequest{'status'} // 200;
			}
			else
			{
				my $template = $$fdata{'rehashes'}{$q};

				if(!$template)
				{
					die 'wtf, $$fdata{\'rehashes\'}{$q} is empty';
				}

				Fuzz::Session::TinyUpdate($fdata, $$customRequest{'sid'}) if $$fdata{'SessionEnabled'};

				Fuzz::Cookies::Set(
					$nginx,
					$$fdata{'SessionKey'},
					$$customRequest{'sid'},
					$$fdata{'SessionExpire'}
				);

				$request_type = Fuzz::MIME::ExtensionToMIMEString(${$template});
				$request_output = Fuzz::Template::Render($fdata, ${$template});

				$nginx->send_http_header($request_type);

				$nginx->print($request_output);

				return 200;
			}

			last;
		}
	}

	return 404;
}

sub extendResponse
{
	my ($n, $r) = @_;

	return if !defined $r or ref($r) ne 'HASH';

	for my $i(keys %{$r})
	{
		$n->header_out($i, $$r{$i}) if $i;
	}
}

sub AddHandler
{
	my ($fdata, $name, $ref, $isAbsolute) = @_;

	die 'handler ' . ref($ref) . ' must be \'CODE\'' if ref($ref) ne 'CODE' && ref($ref) ne 'SCALAR';
	die '\'' . $name . '\' has wrong format (unescaped \'/\' not allowed)' if $name =~ /(?<!\\)\// ;

	$$fdata{'rehashes'}{$isAbsolute ? $name : '^\/' . $name . '$'} = $ref;

	push @{ $$fdata{'rehashesList'} }, $isAbsolute ? $name : '^\/' . $name . '$';
}

sub AddAbsoluteHandler
{
	AddHandler(@_, 1);
}

sub ReverseHandlers
{
	my $fdata = shift;

	reverse @{ $$fdata{'rehashesList'} };
}

1;
__END__
