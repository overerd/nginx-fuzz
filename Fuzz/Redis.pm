package Fuzz::Redis;

use warnings;
use strict;

use Redis;

sub builtIn
{
	my $fdata = shift;

	my $r;

	if($$fdata{'conf'}{'redis_conf'})
	{
		$r = Redis->new($$fdata{'conf'}{'redis_conf'} // {reconnect=>60, every=>5000});
	}
	else
	{
		$r = Redis->new();
	}

	$r->Select($$fdata{'conf'}{'redis_db'}) if $$fdata{'conf'}{'redis_db'};

	return $r;
}

sub new
{
	return Redis->new(@_) if @_;
}

1;
__END__
