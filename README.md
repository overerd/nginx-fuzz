# Wrapper for ngx_http_perl_module (Perl 5.x)

## Preface
Almost 7 years ago I used to write some prototypes using Perl and Nginx. And I decided to write lightweight wrapper for ngx_http_perl_module in order to understand HTTP/1 protocol better (it's headers, multipart parameters, content-disposition headers and so on). It was somewhat of surprise to discover that every single browser back then sended http-request with it's own peculiar differences.

I would be glad if it was useful in some way to someone.

## Uses
You may use it the same way I used it 7 years ago, to study HTTP/1.1 protocol and maybe to write your own implementation of http-body parser, why not?

## Should you use it in production?
Hell no. It's obsolete. And you better not put any heavy logic on ngx_http_perl_module' shoulders. That would be not wise.

## TODO
I assume, that parsing http-request-body using multiple regular expressions is not particularly fast to say the least. It maybe replaced with like HTTP::Body or something along those lines. Templates renderer is not good either.

Well, it was purely academic after all.

## Requirements
It was written with Redis in mind (at least for session storage). So, [Redis](https://redis.io) it is then. And well, also nginx itself (by the way, it still works with nginx 1.13.x).

### CPAN packages:
- URI::Escape
- File::Slurp;
- HTML::Entities
- Redis

## Usage
First of all you need to check [these](http://nginx.org/en/docs/http/ngx_http_perl_module.html) nginx options:
- client_max_body_size;
- client_body_buffer_size;
- client_body_in_file_only.

## Config
Make sure to activate ngx_http_perl_module (in modern versions of nginx). Example:
```
load_module "/usr/local/libexec/nginx/ngx_http_perl_module.so";

http {
 ...
}
```

Then add whole list of required modules in your nginx config file like this:
```
http {
  perl_modules /directory/to/your/perl/modules;

  perl_require module1.pm;
  perl_require module2.pm;

  ...
}
```

And finally configure your location settings:
```
location /testLocation1/ {
  root /root/directory/for/existed/files;

  try_files $uri @MyPerlHandler; # first check $uri for existing files, if file does not exist call named location @MyPerlHandler
}

location @MyPerlHandler
{
  perl Module1::RequestHandler;
}
```

## Example module1.pm:
```
package Module1;

use strict;

use utf8;

use Fuzz::Core;
use Data::Dumper;

sub CustomHandler1
{
  my ($r, @args) = @_; # $r is pointer to $customRequest from Request.pm
                       # @args made of matches from $$config{'map'} and $$config{'amap'} regular expressions

  $$r{'status'} = 301; # override default 302

  # differences in redirection codes:
  # * http 301 Permanent Redirect, would be cached inside client browser
  # * http 302 Found, may return different pages for same request (i.e. /random/ call in picture gallries and so on)

  $$r{'response'}{'Location'} = '/testLocation1/1'; # redirect url
}

sub CustomHandler2
{
  my ($r, @args) = @_;

  if($$r{'post'}) # method POST has been used
  {
    $$r{'nginx'}->send_http_header('text/plain'); # call nginx directly
    
    # also, after calling $nginx->send_http_header you can not use wrapper templates any more, because server already sent headers to the client

    # so now you can also use $nginx->print to send something to the client

    $$r{'nginx'}->print('uri: ' . (Dumper $$r{'uria'}));
    $$r{'nginx'}->print('post: ' . (Dumper $$r{'post'}));
    $$r{'nginx'}->print('files: ' . (Dumper $$r{'files'}));

    return 200;
  } else {
    $$r{'type'} = 'text/html'; # manually set

    $$r{'template'} = 'test.html';

    $$r{'template_escaped'} = 0; # override escape state

    # custom headers may be sent via $$r{'response'}{'Header1'} = 'Test header value';

    $$r{'template_args'} = { # template arguments
      'title' => $$r{'sid'},
      'h1' => 'Test subtitle',
      'h2' => 'test subsubtitle'
    };
  }
}

my $data = {};

my $config = {
  'amap' => { # absolute
    '^\/testLocation1\/?$'       => \&CustomHandler1, # pointer to handler function
    '^\/testLocation1\/(\d+?)?'  => \&CustomHandler2,
    'Q'                          => 'W.html' # static template for every url request with at least one character 'Q' in URL
  },

  'map' => {
    'testLocation1\/(\d+?)' => \&CustomHandler2,
  },

  # first 'amap' then 'map', merged in one list, then reversed
  # each request will iterate those list until match would be found

  'dir'                 => '/www/my_test_app/', # used in $$customRequest{'dir'} inside CustomHandlers
  'dir_templates'       => '/www/my_test_app/t', # same as above; directory for templates (static files like Template1.html also located there)
  'dir_upload'          => '/www/my_test_app/u', # same as above, only it has not been used even once
  'redis'               => {reconnect=>60, every=>5000}, # redis connection options
  'redis_db'            => 6, # redis db selection, like 'use 6;'
  'default_mime'        => 'text/html', #default mime-type, that would be used, if you don't set it manually inside CustomHandlers
  'escaped'             => 1, # escape output in all templates by default
  'escaped_chars'       => '\x22\x26\x3c\x3e\xa0', # escaping char sequence
  'template_clearable'  => 1, # if required parameter was not given inside template, $placeholder would be ereased from the template
  'session_expire'      => 60, # in seconds, self-explanatory
  'session_key'         => 'key' # not a secret, but name for session cookie
};

sub RequestHandler
{
  return Fuzz::Core::RequestHandler(shift, $data, $config);
}
```

The trick is, that $data, $config and any other *global* variable would exist as long as ngx_http_perl_module is active, so don't overdo it with *global* variables in your modules.

You may also want to look inside DemoFuzz.pm and example.pm
Or not.

Have a nice day.