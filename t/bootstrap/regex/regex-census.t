# ABOUTME: script/regex-census.pl lists every regex perl compiles in a file --
# ABOUTME: its op, flags, the features its pattern uses, or that it is built at run time.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);

sub census (@files) {
    my $out = qx($^X script/regex-census.pl --rows @files 2>&1);
    is $? >> 8, 0, 'the census runs' or diag $out;
    return map { my @f = split /\t/; { file => $f[0], line => $f[1], op => $f[2], flags => $f[3], features => { map { $_ => 1 } split /;/, $f[4] }, pattern => $f[5] } }
           grep { /\t/ } split /\n/, $out;
}

my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh <<'EOT';
my $s = "abc";
my $v = "b";
$s =~ /^a(?:b|c)+\z/;
$s =~ s/[|]x\|/y/gr;
my $q = qr/\bfoo.*?bar/i;
sub f { $_[0] =~ /\d{2,3}$/m }
my $g = sub { $_[0] =~ /(?=x)\Qa.b\E/ };
$s =~ /x\Q$v\E/;
$s =~ /a$v/;
my @p = split /,\s*/, $s;
$s =~ tr/a-z/A-Z/;
EOT
close $fh;

my @r = census($pl);
my %by = map { ( $_->{line} => $_ ) } @r;
is scalar(@r), 9, 'one row per regex op, in subs and closures too' or diag explain \@r;

ok $by{3}{features}{alternation} && $by{3}{features}{'non-capture'} && $by{3}{features}{'\\A \\z \\Z'} && $by{3}{features}{'^ anchor'},
    'a match: its alternation, group, anchors' or diag explain $by{3};
ok $by{3}{features}{'quantified group'}, '(?:b|c)+ is a quantified group' or diag explain $by{3};
is $by{3}{op}, 'match', '... as a match';
is $by{4}{op}, 'subst', 'an s///';
is $by{4}{flags}, 'g r', '... its flags';
ok !$by{4}{features}{alternation}, '... a | in a class or escaped is no alternation' or diag explain $by{4};
ok $by{5}{features}{lazy} && $by{5}{features}{'\\b \\B'}, 'a qr//: lazy, \\b' or diag explain $by{5};
is $by{5}{flags}, 'i', '... /i';
ok $by{6}{features}{'counted {n,m}'} && $by{6}{features}{'$ anchor'}, 'in a sub: counted, $' or diag explain $by{6};
ok $by{7}{features}{lookahead}, 'in a closure: lookahead' or diag explain $by{7};
is $by{7}{pattern}, '(?=x)a\\.b', '... a constant \\Q..\\E is applied as perl parses (nothing left to do)';
ok $by{8}{features}{'built at run time'} && $by{8}{features}{'\\Q of a variable'}, '\\Q$v\\E: built at run time, a quotemeta' or diag explain $by{8};
ok !$by{8}{features}{'interpolates a variable'}, '... (the variable is in the quotemeta: a literal)' or diag explain $by{8};
ok $by{9}{features}{'built at run time'} && !$by{9}{features}{'\\Q of a variable'}, 'an interpolated variable: built at run time' or diag explain $by{9};
ok $by{9}{features}{'interpolates a variable'}, '... interpolating it' or diag explain $by{9};
is $by{10}{op}, 'split', 'split by a regex';
ok $by{10}{features}{'\\d \\w \\s'}, '... its \\s';
is $by{11}{op}, 'trans', 'tr///';

done_testing;
