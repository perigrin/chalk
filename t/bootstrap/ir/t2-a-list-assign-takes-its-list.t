# ABOUTME: `my ($x, undef, $y) = LIST` through T2: each target its element by place,
# ABOUTME: undef past the end. A target that takes the rest (an array) is refused.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $src (
    qq{my \@a = (\$ENV{A} // 1, 2, 3);\nmy (undef, \$y, \$z) = \@a;\nprint "\$y \$z\\n";\n},
    qq{my (\$p, \$q) = (\$ENV{P} // 10, 20, 30);\nprint "\$p \$q\\n";\n},
    qq{sub two { return (\$ENV{X} // 4, 5) }\nmy (\$m, \$n, \$o) = two();\nprint "\$m \$n ", defined(\$o) ? "d" : "u", "\\n";\n},
) {
    my $r = tap($src);
    is $r->{verdict}, 'SAME', 'as perl through T2: ' . ( $src =~ s/\n/ /gr ) or diag $r->{why} // explain $r;
}

my $r = tap(qq{my (\$f, \@rest) = (\$ENV{F} // 1, 2, 3);\nprint "\$f \@rest\\n";\n});
is $r->{verdict}, 'REFUSED', 'an array target is refused';
like $r->{why} // '', qr/a list assignment to an array or hash/, '... by name';

done_testing;
