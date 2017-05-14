package Fuzz::Template;

use warnings;
use strict;

use File::Slurp;
use HTML::Entities;

use Data::Dumper;

#TODO: probably need to be rewriten completely without regex
sub Render
{
	my ($fdata, $template_name, $args, $isEscaped, $isRemovable) = @_;

	die '-f $template_name must exist and be not null (' . $template_name  . ')' if ! -f $$fdata{'dir_templates'} . $template_name || !$template_name;

	my $template;

	if($$fdata{'templates'}{$template_name})
	{
		$template = $$fdata{'templates'}{$template_name};
	}
	else
	{
		$$fdata{'templates'}{$template_name} = ( $template = read_file($$fdata{'dir_templates'} . $template_name) );
	}

	if($args)
	{
		if($isEscaped)
		{
			for my $i(keys %{$args})
			{
				my $s = $$args{$i};

				if(ref($s) eq 'HASH')
				{
					if($$s{'escape'})
					{
						$s = EscapeHTMLChars($$s{'value'}, $$fdata{'escaped_chars'});
					}
					else
					{
						$s = $$s{'value'};
					}
				}
				else
				{
					if(ref($s) eq 'ARRAY')
					{
						if($$s[1])
						{
							$s = EscapeHTMLChars($$s[0], $$fdata{'escaped_chars'});
						}
						else
						{
							$s = $$s[0];
						}
					}
					else
					{
						$s = EscapeHTMLChars($s, $$fdata{'escaped_chars'});
					}
				}

				$template =~ s/(?<!\\)(\${$i})/$s/g;
			}
		}
		else
		{
			for my $i(keys %{$args})
			{
				my $s = $$args{$i};

				if(ref($s) eq 'HASH')
				{
					$s = $$s{'value'};
				}
				else
				{
					if(ref($s) eq 'ARRAY')
					{
						$s = $$s[0];
					}
				}

				$template =~ s/(?<!\\)(\${$i})/$s/g;
			}
		}

		$template =~ s/(?<!\\)\${\w+}//g if $isRemovable;
		$template =~ s/\\(.)/$1/g;
	}

	return $template;
}

sub EscapeHTMLChars
{
	return encode_entities(@_);
}

sub EscapeHTMLCharsDefault
{
	my $fdata = shift;

	return EscapeHTMLChars(shift, $$fdata{'escaped_chars'});
}

1;
__END__
