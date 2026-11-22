# ABOUTME: A die of a reference (a hash, an array, an object) caught by an eval leaves the
# ABOUTME: reference itself in $@, not its string: probes ex1-ex4, ev6 print perl's output.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

# WHY. T2's $@ was a die's message, a string: a die of a reference was
# refused where an eval might catch it (WireCheck's W7). On the `eval`
# profile the exception in flight is the value its Exc reads (the runtime's
# pending exception, a Slot), and a die stores what it was given there: a
# reference as itself, anything else as its message with " at FILE line N."
# where it ends in no newline. Its __DIE__ handler would see a string: a die
# of a reference where %SIG is in use stays refused.
my @cases = (
    [ q{eval { die { code => 7 } }; print ref($@), " ", (ref $@ ? $@->{code} : "str"), "\n";}, 'a hash (ex1)' ],
    [ q{eval { die [1,2] }; print ref($@) ? "ref" : "str", "\n";}, 'an array (ex2)' ],
    [ q{package E; sub new { bless { m => $_[1] }, $_[0] } sub msg { $_[0]{m} } package main; eval { die E->new("oops") }; print ref($@) ? $@->msg : "str:$@", "\n";}, 'an object (ex3)' ],
    [ q{my $e; { local $@; eval { die { code => 7 } }; $e = $@ } print ref($e), "\n";}, 'under a local $@ (ex4)' ],
    [ q{my $x = 1; { local $@; eval { $x = 5; die { code => 7 } }; $x += $@->{code} if ref $@ } print "$x\n";}, 'read after the eval (ev6)' ],
    [ q{sub f { die { code => 3 } } eval { f() }; print ref($@), " $@->{code}\n";}, 'from a sub the eval calls' ],
    [ q{my $m = "plain"; eval { die $m }; print $@;}, 'a string by a variable: its message, with its site' ],
    [ q{eval { eval { die [9] }; die $@ }; print ref($@), " $@->[0]\n";}, 'rethrown' ],
);
for my $case (@cases) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $want = qx($^X $pl 2>&1);
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    ok(defined $ll, "$name: lowered through T2") or diag $err // $u->{path_why} // $u->{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got = qx(timeout 20 $LLI $llp 2>&1);
    $got =~ s/ at \S+ line/ at FILE line/g;
    $want =~ s/ at \S+ line/ at FILE line/g;
    is($got, $want, "$name: perl's output");
}
done_testing;
