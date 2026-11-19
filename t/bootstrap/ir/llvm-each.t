# ABOUTME: each %h walks a hash one entry per call -- (key, value), then the empty list
# ABOUTME: once, and again from the start; keys and values reset it. Perl's answer.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

require Chalk::CodeGen::Pipeline;

sub through_llvm ($src, $env) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

# Order-independent programs: perl's hash order is its own (keys emits
# insertion order here), so each is asked only what any order answers.
for my $case (
    [ 'my %h = (a => 7); my ($k, $v) = each %h; print $k, "\n"; print $v, "\n";', 'one entry (pvm 021)' ],
    [ 'my %h = (a => 1); my @x = each %h; my @y = each %h; my @z = each %h; print scalar(@x), scalar(@y), scalar(@z), "\n";',
      'the empty list once, then from the start' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# keys RESETS each, but B::SoN does not order keys among the calls (it is pure
# there): refused by name, not answered from the wrong place.
{
    my $src = 'my %h = (a => 1); my @x = each %h; my @k = keys %h; my @y = each %h; print scalar(@y), "\n";';
    eval { through_llvm($src, {}) };
    like($@, qr/GAP: T2: out of its slices \(\Qan each in a program with a keys or values (which reset it, B::SoN places them nowhere)\E\)/, 'keys between two calls of each: refused');
}

# A while LOOP ON each is a loop shape not lowered yet (a condition with two
# control successors): refused by name.
{
    my $src = 'my %h = (a => 1, b => 2); my $t = 0; while (my ($k, $v) = each %h) { $t += $v } print "$t\n";';
    eval { through_llvm($src, {}) };
    like($@, qr/GAP: /, 'a while loop on each: refused by name');
}

# T2 REFUSES IT, by its reason (only the retired fallback lowered it): each in
# scalar context, refused by name, never a wrong answer.
{
    my $got = eval { through_llvm('my %h = (a => 1); my $k = each %h; my $e = each %h; print $k, defined $e ? "d" : "u", "\n";', {}) };
    ok(!defined $got, 'each in scalar context: T2 lowers no module for it');
    like($@, qr/\Alower: GAP: T2: out of its slices \(\Qan each in scalar context\E\)/, "each in scalar context: refused by T2's reason");
}

done_testing;
