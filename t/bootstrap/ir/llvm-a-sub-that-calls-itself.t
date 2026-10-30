# ABOUTME: a sub that calls itself is emitted once as a function and called, not inlined:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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




# Inlining is the only direct-call mechanism, so `fib(10)` refused ("direct
# call to 'main::fib' is recursive"). A sub that calls itself is a define.
for my $case (
    [ q{use v5.36; sub fib ($n) { return $n < 2 ? $n : fib($n - 1) + fib($n - 2) } print fib(10), "\n";}, 'fib' ],
    [ q{use v5.36; sub fact ($n) { return $n <= 1 ? 1 : $n * fact($n - 1) } print fact(5), " ", fact(1), "\n";}, 'a factorial, twice' ],
    [ q{use v5.36; sub rev ($s) { return length($s) < 2 ? $s : rev(substr($s, 1)) . substr($s, 0, 1) } print rev("abcd"), "\n";}, 'a string result' ],
    [ q{use v5.36; use feature 'class'; no warnings 'experimental::class';
        class Node { field $id :param; method id { return $id } }
        sub ids ($in) { return join(",", map { defined($_) ? $_->id : "undef" } $in->@*) }
        sub fib ($n) { return $n < 2 ? $n : fib($n - 1) + fib($n - 2) }
        print ids([Node->new(id => 1), undef, Node->new(id => 3)]), " ", fib(10), "\n";}, 'pvm 248' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name.
for my $case (
    [ q{use v5.36; sub down ($n) { return 0 if $n < 1; print $n; return down($n - 1) } down(3); print "\n";}, 'a sub that prints, calling itself' ],
    [ q{use v5.36; sub ev ($n) { $n == 0 ? 1 : od($n - 1) } sub od ($n) { $n == 0 ? 0 : ev($n - 1) } print ev(4), "\n";}, 'two subs calling each other' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); next }
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
