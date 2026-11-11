# ABOUTME: substr and index through T2 answer as perl: offsets from either end,
# ABOUTME: a length or none, undef outside the string, -1 where there is no match.
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

my $pre = qq{my \$s = \$ENV{S} // "abcdef";\nsub show { my (\$v) = \@_; print defined(\$v) ? "[\$v]" : "u" }\n};
for my $body (
    q{show(substr($s, 1, 2)); show(substr($s, 3)); show(substr($s, -2)); show(substr($s, 1, -2)); show(substr($s, 0, 0)); print "\n";},
    q{show(substr($s, 6)); show(substr($s, -9)); show(substr($s, 4, 10)); show(substr($s, 2, -9)); print "\n";},
    q{show(substr($s, -9, 3)); show(substr($s, -9, -2)); show(substr($s, -7, 1)); show(substr($s, 6, -1)); show(substr($s, -9, -3)); print "\n";},
    q{print index($s, "cd"), " ", index($s, "x"), " ", index($s, ""), " ", index($s, "c", 3), " ", index($s, "e", 2), " ", index($s, "", 99), "\n";},
) {
    my $r = tap("$pre$body\n");
    is $r->{verdict}, 'SAME', "as perl through T2: $body" or diag $r->{why} // explain $r;
}

# OUTSIDE THE STRING perl answers undef, and warns under `use warnings`, which
# T2 does not know: stopped at run time (exit 255), never half right.
for my $e ( 'substr($s, 7)', 'substr($s, -9, 2)', 'substr($s, -9, -8)', 'substr($s, -7, 0)' ) {
    my $r = tap("$pre show($e); print qq{\\n};\n");
    is $r->{llvm}{exit}, 255, "$e outside the string: stopped" or diag explain $r;
}

done_testing;
