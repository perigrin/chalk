# ABOUTME: T2 slice 14 -- a named hash (my %h) is a hash T2 holds like {...}: its elements,
# ABOUTME: exists, delete, keys and values, a hash from a list (my %o = @_), exists through a reference.
our $LAST_LL;
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

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
    $LAST_LL = $units->[0]{ll};
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
for my $case (
    [ q{my %h = (a => 1, b => 2); $h{c} = 3; print $h{a}, $h{c}, exists $h{b} ? "y" : "n", exists $h{z} ? "y" : "n", "\n";}, 'a literal, a store, exists' ],
    [ q{my %e; $e{x} = 5; $e{y} = 6; print $e{x} + $e{y}, scalar(keys %e), "\n";}, 'an empty hash, stores, keys as a count' ],
    [ q{my %h = (a => 1, b => 2, c => 3); my $d = delete $h{b}; print $d, scalar(keys %h), exists $h{b} ? "y" : "n", $h{c}, "\n";}, 'delete returns the value, the rest kept' ],
    [ q{sub f { my %o = @_; return exists $o{k} ? $o{k} : "none" } print f(k => 4), f(j => 1), "\n";}, 'my %o = @_' ],
    [ q{my $r = {p => 1}; print exists $r->{p} ? 1 : 0, exists $r->{q} ? 1 : 0, "\n";}, 'exists through a reference' ],
    [ q{my %h = (b => 2, a => 1); my $s = ""; for my $k (keys %h) { $s .= $k } my $t = 0; for my $v (values %h) { $t += $v } print length($s), $t, "\n";}, 'keys and values as lists' ],
    [ q{my %h = (a => 1); my $e = exists $h{a}; delete $h{a}; print $e ? "was" : "not", exists $h{a} ? "is" : "gone", "\n";}, 'an exists kept across a delete' ],
    [ q{my %h = (a => 1, b => 2); delete $h{a}; my $x = $h{b}; $h{b} = 9; print $x, $h{b}, "\n";}, 'a read after a delete kept across a store' ],
    [ q{sub n { my ($s) = @_; return length($s) } print length("abc"), length(""), n("xy"), n(12345), "\n";}, 'length of ASCII strings and a number' ],
    [ q{sub n { my ($s) = @_; return length($s) } print defined n(undef) ? "d" : "u", n("ab"), "\n";}, 'length of undef is undef' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# A STRING PAST ASCII: perl's length counts characters, T2's strings are
# bytes -- perl's answer, or refused.
for my $src (q{use utf8; my $s = "\x{e9}t\x{e9}"; print length($s), "\n";}, q{my $s = "caf\x{e9}"; print length($s), "\n";}) {
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "past ASCII: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "past ASCII: refused by name") }
}

done_testing;
