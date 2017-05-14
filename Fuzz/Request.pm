package Fuzz::Request;

use warnings;
use strict;

use URI::Escape;
use File::Slurp;
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

			my %postHash;

			if ($nginx->has_request_body(
					sub
					{
						%postHash = %{readRequestBody($nginx)};
					}
				)
			)
			{
				return 400 if !defined $postHash{'vars'};

				$$customRequest{'post'} = $postHash{'vars'};
				$$customRequest{'files'} = $postHash{'files'};
			}

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

#TODO: probably need to be rewriten completely
sub readRequestBody
{
	my $r = shift;

	my (%vars, $cur_var, $cur_val, $cur_fil);

	my $body;

	if($r->request_body_file)
	{
		$body = read_file($r->request_body_file);
	}
	else
	{
		$body = $r->request_body;
	}

	die 'no request body' if !$body;

	if($r->header_in('Content-Type') eq 'application/x-www-form-urlencoded')
	{
		my %h;

		for(split '&', $body)
		{
			/(\w+(\[\])?)=([^&]*)/;

			if($2)
			{
				if(exists $h{$1})
				{
					push $h{$1}, uri_unescape($3);
				}
				else
				{
					$h{$1} = [uri_unescape($3)];
				}
			}
			else
			{
				$h{$1} = uri_unescape($3);
			}
		}

		for $cur_var(keys %h)
		{
			$vars{'vars'}{$cur_var}{'data'} = $h{$cur_var} // '';
			$vars{'vars'}{$cur_var}{'name'} = $cur_var;
		}

		return \%vars;
	}
	else
	{
		if($r->header_in('Content-Type') =~ /multipart\/form-data/)
		{
			$r->header_in('Content-Type') =~ /boundary=(.+)/;

			my $boundary = '--' . $1;
			my $crlf = qr/\x0D?\x0A/;

			$body =~ s/$boundary(?!--)/$boundary$crlf$boundary/g;
			$body =~ s/^$boundary$crlf//;
			$body =~ s/--\s+?$//;

			my @posts = map { /$boundary[^\n]+\n([^\n]+)\n([^\n]+)\n((?:.|\n)+?)(?:$boundary)/g } $body;

			my $i = @posts;
			my $j = 0;

			my $m;

			$vars{'files'} = [];

			for my $i(@posts)
			{
				$j = 0 if $j > 2;

				if($j == 0)
				{
					$i =~ /Content-Disposition:\s([^;]+);\sname="((?>(?:(?>[^"\\]+)|\\.)*))(\[\])?"(?:;\sfilename="((?>(?:(?>[^"\\]+)|\\.)*))")?/;

					($cur_var, $cur_val, $cur_fil, $cur_mul) = (uri_escape($2), $1, $4, $3);

					my $newFileVar;

					$$newFileVar{'name'} = $cur_var;
					$$newFileVar{'disposition'} = $cur_val;

					if($cur_mul)
					{
						$m = 1;

						if($cur_fil)
						{
							$$newFileVar{'file'} = $cur_fil;

							if( exists($vars{'files'}{$cur_var}) )
							{
								push $vars{'files'}{$cur_var}, $cur_var;
							}
							else
							{
								$vars{'files'}{$cur_var} = [$cur_var];
							}
						}

						if( exists ( $vars{'vars'}{$cur_var} ) )
						{
							push $vars{'vars'}{$cur_var}, $newFileVar;
						}
						else
						{
							$vars{'vars'}{$cur_var} = [$newFileVar];
						}
					}
					else
					{
						$m = 0;

						if($cur_fil)
						{
							$$newFileVar{'file'} = $cur_fil;
							$vars{'files'}{$cur_fil}{'name'} = $cur_var;
						}

						$vars{'vars'}{$cur_var} = $newFileVar;
					}
				}
				else
				{
					if($j == 1)
					{
						$i =~ /Content-Type:\s([\w\-]+\/[\w\-+]+)/;

						$vars{'files'}{uri_escape($vars{'vars'}{$cur_var}{'file'})}{'type'} = $1 if $1;
					}
					else
					{
						$i =~ s/$crlf$//;

						if($m)
						{
							$m = $#{$vars{'vars'}{$cur_var}};

							$vars{'vars'}{$cur_var}[$m]{'data'} = $i if !$vars{'vars'}{$cur_var}[$m]{'file'};

							if($i && $cur_fil)
							{
								$i =~ s/^$crlf//;

								$vars{'files'}{uri_escape($cur_fil)}{'data'} = $i;
							}
						}
						else
						{
							$vars{'vars'}{$cur_var}{'data'} = $i if !$vars{'vars'}{$cur_var}{'file'};

							if($i && $cur_fil)
							{
								$i =~ s/^$crlf//;

								$vars{'files'}{uri_escape($vars{'vars'}{$cur_var}{'file'})}{'data'} = $i;
							}
						}
					}
				}
				$j++;
			}
			return \%vars;
		}
	}
}

1;
__END__
