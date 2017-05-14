package Fuzz::Cookies;

use warnings;
use strict;

use URI::Escape;

my @days = qw(Mon Tue Wed Thu Fri Sat Sun);
my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

sub Read
{
	my %hash = map { /(.+)=(.*)/ => $1, uri_unescape($2) } split /;\s*/, shift;

	return \%hash;
}

sub GetGMTString
{
	my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime(shift);

	$sec = '0' . $sec if length($sec) < 2;
	$min = '0' . $min if length($min) < 2;
	$hour = '0' . $hour if length($hour) < 2;
	$mday = '0' . $mday if length($mday) < 2;

	return $days[$wday] . ", $mday-" . $months[$mon] . '-' . (1900 + $year) . " $hour:$min:$sec GMT";
}

sub Set
{
	my ($r, $name, $value, $time, $secure, $path, $domain) = @_;

	$r->header_out(
		'Set-Cookie',
		"$name=" . uri_escape($value)
			. '; expires=' . GetGMTString($time > 0 ? ( time + $time ) : 0)
			. '; path=' . ($path // '/') . ';'
			. ($domain ? " Domain=$domain;" : '')
			. ($secure ? ' Secure;' : '')
			. ' HttpOnly'
	);
}

sub SetBySeconds
{
	Set(@_);
}

sub SetByDays
{
	my ($r, $name, $value, $days, $secure, $path, $domain) = @_;

	SetBySeconds($r, $name, $value, 86400 * ($days // 1), $secure, $path, $domain);
}

sub Update
{
	my ($nginx, $fdata, $old, $new) = @_;

	for my $cookie(keys %{$old})
	{
		Fuzz::Cookies::Set($nginx, $cookie, '', 0) if !defined $$new{$cookie};
	}

	for my $cookie(keys %{$new})
	{
		if(ref($$new{$cookie}) eq 'SCALAR' || ref(\$$new{$cookie}) eq 'SCALAR' && $$new{$cookie})
		{
			Fuzz::Cookies::Set(
				$nginx,
				$cookie,
				$$new{$cookie},
				$$fdata{'CookiesExpire'},
				$$fdata{'SecuredConnection'},
				'',
				$$fdata{'CookiesDomain'}
			)
				if !defined $$old{$cookie}
					|| $$new{$cookie} ne $$old{$cookie};
		}
		else
		{
			if(ref($$new{$cookie}) eq 'HASH')
			{
				if(!defined $$old{$cookie} || $$new{$cookie}{'value'} ne $$old{$cookie})
				{
					if($$new{$cookie}{'bydays'})
					{
						Fuzz::Cookies::SetByDays(
							$nginx,
							$cookie,
							$$new{$cookie}{'value'},
							$$new{$cookie}{'time'} // $$fdata{'CookiesExpire'},
							$$fdata{'SecuredConnection'},
							$$new{$cookie}{'path'},
							$$new{$cookie}{'domain'} // $$fdata{'CookiesDomain'}
						);
					}
					else
					{
						Fuzz::Cookies::Set(
							$nginx,
							$cookie,
							$$new{$cookie}{'value'},
							$$new{$cookie}{'time'} // $$fdata{'CookiesExpire'},
							$$fdata{'SecuredConnection'},
							$$new{$cookie}{'path'},
							$$new{$cookie}{'domain'} // $$fdata{'CookiesDomain'}
						);
					}
				}
			}
			else
			{
				if(ref($$new{$cookie}) eq 'ARRAY')
				{
					if(!defined $$old{$cookie} || $$new{$cookie}[0] ne $$old{$cookie})
					{
						Fuzz::Cookies::SetByDays(
							$nginx,
							$cookie,
							$$new{$cookie}[0],
							$$new{$cookie}[1] // $$fdata{'CookiesExpire'},
							$$fdata{'SecuredConnection'},
							$$new{$cookie}[2],
							$$new{$cookie}[3] // $$fdata{'CookiesDomain'}
						);
					}
				}
				else
				{
					die '$$new{$cookie} has wrong format (must be SCALAR or a HASH; currently is ' . ref($cookie) . ')';
				}
			}
		}
	}
}

1;
__END__
