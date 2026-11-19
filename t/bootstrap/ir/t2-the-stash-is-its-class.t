# ABOUTME: A stash is a hash whose metaobject is its package's Chalk::MOP::Class, carried from the
# ABOUTME: compile into the run: exists and truth answered from the Class's symbols; no tie.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

sub t2 ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = ( $units // [] )->[0] // {};
    return ( !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef, $err // $u->{path_why} // $u->{err}, $pl );
}

sub lli ($ll) {
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lf, ':utf8'; print $lf $ll; close $lf;
    return run("timeout 20 $LLI $llp");
}

for my $case (
    [ qq{our \$answer = 42;\nprint exists \$::{answer} ? "y" : "n", exists \$::{nosuch} ? "y" : "n", "\\n";\n}, 'exists: an our is there, nothing made nosuch' ],
    [ qq{use POSIX;\nprint \$main::{"floor"} ? "yes" : "no", "\\n";\n}, 'an import is a symbol of main' ],
    [ qq{use POSIX ();\nprint \$main::{"floor"} ? "yes" : "no", "\\n";\n}, 'use POSIX () imports none' ],
    [ qq{our \$x = 1;\nprint tied(%main::) ? "t" : "u", "\\n";\n}, 'a stash is no tie' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $why, $pl) = t2($src);
    ok(defined $ll, "$name: lowered through T2") or diag $why;
    next unless defined $ll;
    my $got  = lli($ll);
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# AN ENTRY'S VALUE is a glob, whose slots are the stash's: read only as a truth.
{
    my ($ll, $why) = t2(qq{our \$answer = 1;\nprint \$::{answer}, "\\n";\n});
    ok(!defined $ll, 'a stash entry printed: not lowered');
    like($why // '', qr/a value of %main:: read as other than a truth/, '... refused by name');
}

# A NAME THE TOOLCHAIN MADE before the program compiled: plain perl may or may
# not have it -- stopped by name when asked.
{
    my ($ll, $why) = t2(qq{our \$x = 1;\nprint exists \$::{SIG} ? "y" : "n", "\\n";\n});
    ok(defined $ll, 'an exists of a name the toolchain made: lowered') or diag $why;
    if (defined $ll) {
        my $got = lli($ll);
        is($got->[2], 255, '... stopped');
        like($got->[1], qr/chalk: refused at run time: whether main:: holds SIG/, '... by name');
    }
}

# A PROGRAM THAT MAY CHANGE ITS STASH WHILE IT RUNS (a delete from it, a
# symbolic deref, a string eval -- the loader's $STASH_CHANGES): the symbols
# the compile saw may be stale, so its stash is refused by name.
{
    my ($ll, $why) = t2(qq{our \$x = 1;\ndelete \$::{x} if \$ENV{D};\nprint exists \$::{x} ? "y" : "n", "\\n";\n});
    ok(!defined $ll, 'a stash the program may change: not lowered');
    like($why // '', qr/a stash where the program may change it at run time \(a store to or delete from the stash\)/, '... refused by name, the loader\'s reason');
}

done_testing;
