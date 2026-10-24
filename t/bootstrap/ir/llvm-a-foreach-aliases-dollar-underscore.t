# ABOUTME: A foreach whose callees read $_ aliases $_ to each element: reads and writes
# ABOUTME: by name reach the element, and the pass restores $_ -- B::SoN -> chalk -> lli == perl.
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

# `local *_ = \$a[$i]` (B::SoN's LocalAlias) makes `$_` the element for a
# callee that reads or writes it by name. `$_` is read through a pointer the
# alias moves, so the element and `$_` are one cell; the loop's exit points
# it back (7 pvm cases refused "cannot lower op=LocalAlias").
for my $case (
    [ q{sub bump { $_ .= "!" } sub f { my @a = (1, 2); $_ = "top"; bump() for @a; return "$_|@a" } print f(), "\n";}, "top|1! 2!\n", 'a callee writes the element through $_' ],
    [ q{sub g { $_[0] = $_[0] * 10 } sub f { my @n = (1, 2); g($_) for @n; return "@n" } print f(), "\n";}, "10 20\n", 'and hands it on' ],
    [ q{sub is_x { /x/ } sub show { print $_ } sub f { my @a = qw(ax b xc); show() for @a; show() for 1 .. 2; return "" } print f(), "\n";}, "axbxc12\n", 'over an array and over a range' ],
    [ q{sub show { print $_ } $_ = "top"; my @o = qw(a b); my @i = qw(x y); for (@o) { show(); for (@i) { show() } show() } print "[$_]\n";}, "axyabxyb[top]\n", 'nested passes restore in turn' ],
    [ q{sub show { print $_ } $_ = "top"; for (qw(a b c)) { last if $_ eq "b"; show() } print "[$_]\n";}, "a[top]\n", 'a last restores too' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
