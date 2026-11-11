# ABOUTME: the differential harness runs a test program under perl and through B::SoN,
# ABOUTME: T2 and lli, and compares stdout, stderr and exit status byte for byte.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub file_of ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return $pl;
}

my $r = Chalk::CodeGen::Harness::TapDiff->compare( file_of(qq{print "ok 1\\n";\nprint "1..1\\n";\n}) );
is $r->{verdict}, 'SAME', 'TAP on stdout: the same through T2' or diag explain $r;
is $r->{llvm}{out}, "ok 1\n1..1\n", '... the compiled run\'s stdout is kept';

$r = Chalk::CodeGen::Harness::TapDiff->compare( file_of(qq{print [], "\\n";\n}) );
is $r->{verdict}, 'DIFFERS', 'an address printed differs' or diag explain $r;

$r = Chalk::CodeGen::Harness::TapDiff->compare( file_of(qq{my \$m = \$ENV{M} // "X.pm";\nrequire \$m;\nprint "ok\\n";\n}) );
is $r->{verdict}, 'REFUSED', 'a program T2 does not compile is refused';
like $r->{why}, qr/\AT2: /, '... with the reason';
unlike $r->{why}, qr/\AT2: T2:/, '... said once';

# STDERR AND EXIT STATUS are compared too; their cases arrive with the T2
# support Test::Chalk's diag and BAIL_OUT need (print STDERR, exit).
is_deeply [ sort keys %{ $r->{perl} } ], [qw(err exit out)], 'perl\'s stdout, stderr and exit are kept';

# FROM THE COMMAND LINE: one line per file, exit 0 when every file is the same.
my $same = file_of(qq{print "ok 1\\n1..1\\n";\n});
my $out  = qx($^X -Ilib -It/lib t/lib/Chalk/CodeGen/Harness/TapDiff.pm $same 2>&1);
is $? >> 8, 0, 'the command exits 0 when the TAP is the same' or diag $out;
like $out, qr/\ASAME\s+\Q$same\E$/m, '... and says so';
$out = qx($^X -Ilib -It/lib t/lib/Chalk/CodeGen/Harness/TapDiff.pm @{[ file_of(qq{print [], "\\n";\n}) ]} 2>&1);
is $? >> 8, 1, 'and 1 when one differs';

done_testing;
