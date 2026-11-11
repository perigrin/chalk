# ABOUTME: T2 prints to STDOUT and STDERR by name and exits with a status, as perl does:
# ABOUTME: what Test::Chalk's diag and BAIL_OUT need. Another filehandle is refused by name.
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
    qq{print STDERR "# e\\n";\nprint "ok 1\\n";\n},
    qq{print STDOUT "ok 1\\n";\nprint STDERR "# a ", 2, "\\n";\n},
    qq{print {*STDERR} "# x\\n";\nprint "ok\\n";\n},
    qq{print "a\\n";\nexit 3;\nprint "b\\n";\n},
    qq{sub bail { print "Bail out!\\n"; exit 255 }\nprint "ok 1\\n";\nbail() if \$ENV{X} // 1;\nprint "ok 2\\n";\n},
    qq{my \$n = \$ENV{N} // 0;\nexit \$n;\n},
) {
    my $r = tap($src);
    is $r->{verdict}, 'SAME', 'as perl through T2: ' . ( $src =~ s/\n/ /gr ) or diag $r->{why};
}

my $r = tap(qq{open my \$fh, '>', '/dev/null';\nprint \$fh "x\\n";\nprint "ok\\n";\n});
is $r->{verdict}, 'REFUSED', 'a print to another filehandle is refused';
like $r->{why} // '', qr/a print to a filehandle other than STDOUT or STDERR|T2: /, '... by name';

done_testing;
