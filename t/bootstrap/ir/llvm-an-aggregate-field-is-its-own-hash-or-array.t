# ABOUTME: a `field %h` or `field @a` is an aggregate of the object's own, made empty by
# ABOUTME: new and reached by the methods: B::SoN -> chalk -> lli == perl.
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

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
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
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}


# B::SoN declares no type for an aggregate field; it was refused (pvm 242).
for my $c (
    [ q{use feature "class"; no warnings "experimental::class"; class Index { field %id_for; field $count = 0; method register ($key) { return $id_for{$key} if exists $id_for{$key}; my $id = $count++; $id_for{$key} = $id; return $id; } } my $ix = Index->new; print join(",", $ix->register("a"), $ix->register("b"), $ix->register("a"), $ix->register("c")), "\n";} ],
    [ q{use feature "class"; no warnings "experimental::class"; class Q { field @items; method add ($x) { push @items, $x; return scalar @items } } my $q = Q->new; $q->add("a"); print $q->add("b"), "\n";} ],
    # Each object has its own.
    [ q{use feature "class"; no warnings "experimental::class"; class C { field %m; method add ($k) { $m{$k} = 1 } method has ($k) { exists $m{$k} ? 1 : 0 } } my $x = C->new; my $y = C->new; $x->add("a"); print $x->has("a"), $y->has("a"), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
