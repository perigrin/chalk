# ABOUTME: An inlined callee that reads @_ as a list reads an array of the call's
# ABOUTME: arguments; one that writes through @_, or shifts it first, is refused.
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

# `for my $x (@_)`, "@_", scalar(@_), `my @p = @_`: 21 pvm corpus cases were
# refused as "callee accesses @_ as an aggregate". Reading it, @_ is an array
# of the call's arguments, built at the call -- a copy, which is exactly
# what a read cannot tell from the aliases perl passes.
for my $case (
    [ q{sub f { for my $x (@_) { print "<$x>" } return 1 } f(1, "b", 3); print "\n";}, "<1><b><3>\n", 'a foreach over @_' ],
    [ q{sub f { return "f[@_]" } print f(1, 2), "\n";}, "f[1 2]\n", '@_ interpolated' ],
    [ q{sub f { return scalar(@_) } print f(4, 5, 6), "\n";}, "3\n", 'its count' ],
    [ q{sub f { return $_[0] . "-" . $_[1] . "-" . scalar(@_) } print f("a", "b"), "\n";}, "a-b-2\n", 'elements and count' ],
    [ q{sub f { return join(",", @_) } print f(1, 2, 3), "\n";}, "1,2,3\n", 'joined' ],
    [ q{sub f { return scalar(@_) } print f(1), f(1, 2), "\n";}, "12\n", 'each call its own' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A WRITE THROUGH @_ reaches the caller's variable; a shift takes an element
# out of it. A copy has neither: refused, or right -- never the copy's answer.
for my $case (
    [ q{sub f { $_[0] = 9; return scalar(@_) } my $v = 1; f($v); print "$v\n";}, "9\n", 'a store to $_[0]' ],
    [ q{sub f { my $a = shift; return "$a:@_" } print f(1, 2, 3), "\n";}, "1:2 3\n", 'a shift, then @_' ],
    [ q{sub f { my @p = @_; push @p, 9; return "@p|@_" } print f(1, 2), "\n";}, "1 2 9|1 2\n", 'a copy of it is a copy' ],
    # AN ITERATOR HANDED TO A CALL is aliased by reference -- `exists
    # $_[$i] ? \$_[$i] : ...` -- which reads @_ and writes nothing; the
    # reference itself is not lowered yet.
    [ q{sub id { $_[0] } sub f { my $s = ""; for my $x (@_) { $s = $s . id($x) } return $s } print f("a", "b"), "\n";}, "ab\n", 'an iterator handed to a call' ],
    # A WRITE THROUGH A REFERENCE to an element writes the caller's $v.
    [ q{sub f { my $n = scalar(@_); my $r = \$_[0]; $$r = 5; return $n } my $v = 1; my $k = f($v); print "$v $k\n";}, "5 1\n", 'a store through a reference to $_[0]' ],
    [ q{sub f { my %o = @_; return $o{b} } print f(a => 1, b => 2), "\n";}, "2\n", 'a hash built from @_' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    ok(defined $got ? $got eq $want : $@ =~ /^(?:load|lower): /,
        "$name: refused, or perl's answer")
        or diag defined $got ? "got: $got" : $@;
}

done_testing;
