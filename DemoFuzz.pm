package DemoFuzz;

use strict;

use utf8;

use Fuzz::Core;
use Fuzz::Template;
use Data::Dumper;

my $demoData = {};

sub UploadHandler
{
	my ($r, @args) = @_;

	if($$r{'post'})
	{
		$$r{'nginx'}->send_http_header('text/plain');

		$$r{'nginx'}->print('uri: ' . (Dumper $$r{'uria'}));
		$$r{'nginx'}->print('post: ' . (Dumper $$r{'post'}));
		$$r{'nginx'}->print('files: ' . (Dumper $$r{'files'}));

		return 200;
	}

	$$r{'response'}{'Location'} = '/u';
}

sub UploadViewHandler
{
	my ($r, @args) = @_;

	$$r{'nginx'}->send_http_header('text/html');

	$$r{'nginx'}->print('<form method="post">
		<input type="hidden" name="hiddenVal" value="test"/>
		<input name="tval" value=""/>
		<input type="checkbox" name="cbox1"/>
		<input type="checkbox" name="cbox2" checked/>
		<input type="file" name="file1"/>

		<button>Post!</button>
	</form></br>');

	$$r{'nginx'}->print('<form method="get">
		<input type="hidden" name="hiddenVal" value="test"/>
		<input name="tval" value=""/>
		<input type="checkbox" name="cbox1"/>
		<input type="checkbox" name="cbox2" checked/>

		<button>Get!</button>
	</form></br>');

	$$r{'nginx'}->print('<form method="post" enctype="multipart/form-data">
		<input type="hidden" name="hiddenVal" value="test"/>
		<input name="tval" value=""/>
		<input type="file" name="file1"/>
		<input type="file" name="file2"/>

		<button>Get!</button>
	</form></br>');

	return 200;
}

sub TemplateHandler
{
	my ($r, @args) = @_;

	$$r{'type'} = 'text/html';
	$$r{'template'} = 'test.html';
	$$r{'template_escaped'} = 0;
	$$r{'template_args'} = {
		'title' => $$r{'sid'},
		'h1' => 'Test subtitle',
		'h2' => 'test subsubtitle'
	};
}

sub TemplateRenderHandler
{
	my ($r, @args) = @_;

	$$r{'raw'} = 1;

	$$r{'nginx'}->send_http_header('text/html');

	$$r{'nginx'}->print(
		Fuzz::Template::Render(
			$demoData,
			'test2.html'
			,{'pre' => (Dumper $$r{'post'}) . (Dumper $$r{'files'}) . "<br/>"}
		)
	);
}

my $demoConfig = {
	'map'=>{
		'u'		=>	\&UploadViewHandler,
		'upl'		=>	\&UploadHandler,
		't'		=>	\&TemplateRenderHandler,
		't2'		=>	\'test2.html'
	},

	'amap'=>{
		'^\/$'		=>\&TemplateHandler
	},

	'dir'			=>'/www/fuzz/',
	'dir_upload'		=>'/www/fuzz/u',
	'dir_templates'		=>'/www/t',
	'redis'			=>{reconnect=>60, every=>5000},
	'redis_db'		=>1,
	'default_mime'		=>'text/html',
	'escaped'		=>1,
	'escaped_chars'		=>'\x22\x26\x3c\x3e\xa0',
	'template_clearable'	=>1,
	'session_expire'	=>60, #in seconds
	'session_key'		=>'key'
};

sub RequestHandler
{
	return Fuzz::Core::RequestHandler(shift, $demoData, $demoConfig);
}

__END__
