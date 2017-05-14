package Fuzz::Session;

use warnings;
use strict;

use Fuzz::Redis;
use UUID::Tiny;

sub new
{
	my ($fdata, $ip, $sid) = @_;

	my $uuid;

	my $r = Fuzz::Redis::builtIn($fdata);

	die 'redis error' if !$r;

	my $sip = $r->get('s'. $sid) // '';

	if($sip)
	{
		return $sid if defined $sid && $sid ne '' && $ip eq $sip;
	}

	while(!defined $uuid || $r->exists('s' . $uuid))
	{
		$uuid = UUID_to_string(create_UUID(UUID_V4));
		$uuid =~ s/-//g;
	}

	$r->set('s' . $uuid, $ip);
	$r->hset($uuid, 'session_expire', time + ($$fdata{'SessionExpire'}));
	$r->expire($uuid, $$fdata{'SessionExpire'}) if $r->exists($uuid);
	$r->expire('s' . $uuid, $$fdata{'SessionExpire'});

	return $uuid;
}

sub Load
{
	my $fdata = shift;
	my $sid = shift;

	die '$sid must be not null' if !defined $sid;

	my$r = Fuzz::Redis::builtIn($fdata);

	if($r->exists($sid))
	{
		my %res;
		my $s;

		for my $i($r->hgetall($sid))
		{
			$s = $r->hget($sid, $i);
			$res{$i} = $s if defined $s;
		}

		return \%res;
	}

	return undef;
}

sub Update
{
	my ($fdata, $sid, $data) = @_;

	die '$sid must be not null'if !defined $sid;

	my $r = Fuzz::Redis::builtIn($fdata);

	if(scalar(keys %{$data}) > 0)
	{
		for my $i(keys %{$data})
		{
			if(defined $$data{$i})
			{
				$r->hset($sid, $i, $$data{$i});
			}
			else
			{
				$r->hdel($sid, $i);
			}
		}
	}

	$r->hset($sid, 'session_expire', time + ($$fdata{'SessionExpire'}));
	$r->expire($sid, $$fdata{'SessionExpire'}) if $r->exists($sid);
	$r->expire('s' . $sid, $$fdata{'SessionExpire'}) if $r->exists('s' . $sid);
}

sub TinyUpdate
{
	my ($fdata, $sid) = @_;

	die '$sid must be not null' if !defined $sid;

	my $r = Fuzz::Redis::builtIn($fdata);

	$r->hset($sid, 'session_expire', time + ($$fdata{'SessionExpire'}));
	$r->expire($sid, $$fdata{'SessionExpire'}) if $r->exists($sid);
	$r->expire('s' . $sid, $$fdata{'SessionExpire'}) if $r->exists('s' . $sid);
}

sub Purge
{
	my ($fdata, $sid) = @_;

	die '$sid must be not null' if !defined $sid;

	my $r = Fuzz::Redis::builtIn($fdata);

	$r->expire($sid, -1);
	$r->expire('s' . $sid, -1) if $r->exists('s' . $sid);
}

1;
__END__
