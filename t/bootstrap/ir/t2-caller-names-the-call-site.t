# ABOUTME: caller through T2: the package, file and line of the call a sub is in, N
# ABOUTME: frames up -- what Test::Chalk's "at FILE line N" needs. Read past [2] it refuses.
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
    qq{sub f { my (\$p, \$file, \$line) = caller; print "\$p \$line\\n" }\nf();\n},
    qq{sub f { my (undef, \$file, \$line) = caller(0); print "\$file \$line\\n" }\nsub g {\n f();\n}\ng();\n},
    qq{sub f { my (undef, undef, \$line) = caller(1); print "\$line\\n" }\nsub g { f() }\n\ng();\n},
    qq{my \@c = caller;\nprint scalar(\@c), "\\n";\n},
    qq{sub f { my (\$p) = caller(5); print defined(\$p) ? "some\\n" : "none\\n" }\nf();\n},
    qq{sub f { print scalar(caller), "\\n" }\npackage P;\nmain::f();\n},
    qq{package C;\nsub m { my \@c = caller; print "\$c[0] \$c[2]\\n" }\npackage main;\nC->m;\n},
) {
    my $r = tap($src);
    is $r->{verdict}, 'SAME', 'as perl through T2: ' . ( $src =~ s/\n/ /gr ) or diag $r->{why} // explain $r;
}

# caller(N) GIVES ELEVEN VALUES; T2 knows the first three (hints and the
# rest are perl's own). A read past them is refused, not answered wrong.
my $r = tap(qq{sub f { my \@c = caller(0); print scalar(\@c), "\\n" }\nf();\n});
is $r->{verdict}, 'REFUSED', 'caller(N) read whole is refused';
like $r->{why} // '', qr/caller\(N\) read past its third value/, '... by name';

done_testing;
