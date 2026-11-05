# ABOUTME: a method returning `values` or `keys` of a field hash returns that list: a
# ABOUTME: call in list context reads it, one in scalar context its count, as perl.
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

my $class = q{use feature "class"; no warnings "experimental::class";
class Registry {
    field %classes;
    method add ($name) { $classes{$name} = 1; return $self }
    method classes { return values %classes }
    method names { return keys %classes }
}
};
for my $case (
    [ q{my $r = Registry->new; $r->add("A"); $r->add("B"); my @all = $r->classes; print scalar(@all), "\n";}, 'list context' ],
    [ q{my $r = Registry->new; $r->add("A"); $r->add("B"); my $n = $r->classes; print "$n\n";}, 'scalar context: the count' ],
    [ q{my $r = Registry->new->add("A")->add("B"); my @all = $r->classes; my $n = $r->classes; print scalar(@all), " $n\n";}, 'pvm 246: both, after a chain' ],
    [ q{my $r = Registry->new; $r->add("x"); my @k = $r->names; my $n = $r->names; print join(",", @k), " $n\n";}, 'keys, both contexts' ],
) {
    my ($src, $name) = @$case;
    $src = $class . $src;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# A FIELD HASH NOTHING STORES TO arrives untyped: perl's answer, or refused.
{
    my $src = $class . q{my $r = Registry->new; my $n = $r->classes; my @a = $r->classes; print "$n ", scalar(@a), "\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "an empty hash: perl's answer") }
    else { like($@, qr/GAP|lattice TOP/, 'an empty hash: refused by name') }
}

done_testing;
