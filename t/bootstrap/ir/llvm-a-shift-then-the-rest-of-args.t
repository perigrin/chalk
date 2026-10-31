# ABOUTME: a callee that shifts @_ and then reads the rest of it as a list -- the
# ABOUTME: package constructor's `shift; bless {@_}` -- gets the arguments past the shifted.
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




# After its shifts, @_ is the arguments past them. Refused before as "callee
# shifts @_ and reads it as a list" (pvm 147).
for my $case (
    [ q{package K { sub new { shift; bless {@_}, "K" } }
        sub f { my ($s, $p) = @_; my $o = K->new(name => "n", (defined $s ? (superclass => $s) : ()), (defined $p ? (parent => $p) : ())); return join ",", map { "$_=$o->{$_}" } sort keys %$o }
        print f("S", undef), " ", f(undef, "P"), "\n";}, 'pvm 147' ],
    [ q{sub rest { my $first = shift; return $first . ":" . join("-", @_) } print rest("a", "b", "c"), " ", rest("z"), "\n";}, 'the rest joined' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: a list read that comes before a shift,
# or one the graph does not order (`my %a = @_` is a HashLiteral with no
# control or memory position).
for my $case (
    [ q{sub mk { my $class = shift; my %a = @_; return join ",", $class, map { "$_=$a{$_}" } sort keys %a } print mk("C", x => 1, y => 2), "\n";}, 'a class, then a hash of the rest (unordered)' ],
    [ q{sub odd { my $n = scalar(@_); my $f = shift; return "$n $f" } print odd("a", "b"), "\n";}, 'counted before the shift' ],
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
