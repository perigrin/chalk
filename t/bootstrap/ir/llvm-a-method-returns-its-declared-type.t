# ABOUTME: A method body returns what its declared type says -- a bare `return` is an
# ABOUTME: empty list -- or is refused by name; never a module lli rejects.
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

# A BARE `return` IS AN EMPTY LIST. The method was declared `%Array*` and its
# return emitted `ret i64` over the list pointer; lli rejected the module
# (pvm corpus class-feature.md, an ADJUST calling `$self->mark("d")`).
for my $case (
    [ q{use v5.42; use experimental "class"; class K { method nada { return } } K->new->nada; print "ok\n";}, "ok\n", 'a method returning nothing' ],
    [ q{use v5.42; use experimental "class"; class K { field $t = ""; method mark ($c) { $t .= $c; return } method t { $t } } my $k = K->new; $k->mark("x"); print $k->t, "\n";}, "x\n", 'a method that stores and returns nothing' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "$name: perl's answer") }
    else { like($@, qr/^(?:load|lower): .*(?:GAP|LLVM backend:)/, "$name: refused, naming why") or diag $@ }
}

done_testing;
