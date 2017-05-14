package Fuzz::MIME;

use warnings;
use strict;

my %extensions = (
	'html'	=>	'text/html',
	'htm'	=>	'text/html',
	'xhtml'	=>	'application/xhtml+xml',
	'txt'	=>	'text/plain',
	'css'	=>	'text/css',
	'js'	=>	'application/javascript',
	'json'	=>	'application/json',
	'csv'	=>	'text/csv',
	'xml'	=>	'text/xml',
	'ps'	=>	'application/postscript',
	'soap'	=>	'application/soap+xml',
	'dtd'	=>	'application/xml-dtd',
	'zip'	=>	'application/zip',
	'svg'	=>	'image/svg+xml',
	'raw'	=>	'application/octet-stream',
	'pdf'	=>	'application/pdf'
);

my %reversedExtensions = map {$extensions{$_}, $_} keys %extensions;

sub ExtensionToMIMEString
{
	shift =~ /\.([A-Za-z0-9]+)$/;

	if($1)
	{
		return $extensions{$1} // 'application/octet-stream';
	}

	return 'application/octet-stream';
}

sub MIMEStringToExtension
{
	my $t = shift;
	if($t)
	{
		$t =~ /\.(\w+)$/;
		$t = $1 if $1;
		return $reversedExtensions{$t} // 'raw';
	}
}

1;
__END__
