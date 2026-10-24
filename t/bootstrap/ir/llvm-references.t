# ABOUTME: References: \@a, \%h and \$x share their referent's storage, $$r reads and
# ABOUTME: writes it, ref() names its kind: through B::SoN -> chalk -> lli == perl.
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

# `\` WAS NOT LOWERED ("cannot lower op=Ref", 14 pvm corpus cases; RefType
# and a scalar deref beside it). An %Array or %Hash is already one heap
# object, so a reference to it IS it, as a ref; a scalar reference points
# at the variable's %Slot, which taking a reference makes a location.
for my $case (
    [ q{my @a = (10, 20, 30); my $r = \@a; my @c = @{$r}; print scalar(@c), " ", "@{$r}\n";}, "3 10 20 30\n", 'an array through its reference' ],
    [ q{sub add { my ($h) = @_; $h->{b} = 2; 2 } my %p = (a => 1); add(\%p); print exists $p{b} ? "y" : "n", $p{b}, "\n";}, "y2\n", 'a hash written through a reference a sub holds' ],
    [ q{my @a = (1, 2); my $r = \@a; $r->[0] = 7; print "@a\n";}, "7 2\n", 'an element written through a reference' ],
    [ q{my $n = 5; my $sr = \$n; print $$sr, "\n"; $$sr = 6; print "$n\n";}, "5\n6\n", 'a scalar read and written through one' ],
    [ q{my $r = [10, 20, 30]; print scalar(@$r), " ", ref($r), "\n";}, "3 ARRAY\n", 'ref of an anonymous array' ],
    [ q{my %h = (k => 1); my $n = 5; print ref(\%h), " ", ref(\$n), " [", ref($n), "]\n";}, "HASH SCALAR []\n", 'ref of each kind, and of none' ],
    [ q{sub w { $_[0][$_[1]] = "z"; 1 } my @a = qw(a b c); w(\@a, 1); print "@a\n";}, "a z c\n", 'a sub writes through the reference it is handed' ],
    # AN EMPTY HASH, filled: `my %h;` is a bare % PadAccess, and was refused
    # ("PadAccess has no VarDecl input"); each new key is an insert.
    [ q{my %h; for my $i (1 .. 6) { $h{"k$i"} = $i * 2 } print $h{k1} + $h{k6}, " ", scalar(keys %h), "\n";}, "14 6\n", 'an empty hash filled in a loop' ],
    [ q{sub inc { my ($h, $k) = @_; $h->{$k} = ($h->{$k} // 0) + 1 } my %c; inc(\%c, "x"); inc(\%c, "x"); inc(\%c, "y"); print "$c{x}$c{y}\n";}, "21\n", 'a counting hash a sub fills' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A COPY THROUGH A REFERENCE IS A COPY: `my %p = %$h` aliased the hash, and
# a store through $h after it showed in %p (2 2 for perl's 1 2).
for my $case (
    [ q{sub f { my ($h) = @_; my %p = %$h; $h->{a} = 2; return "$p{a} $h->{a}" } print f({a=>1}), "\n";}, "1 2\n", 'a hash copied through its reference' ],
    [ q{sub f { my ($h) = @_; my @p = @$h; $h->[0] = 2; return "$p[0] $h->[0]" } print f([1]), "\n";}, "1 2\n", 'an array copied through its reference' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# AN ARGUMENT THE CALLEE LEAVES UNKNOWN is the caller's value as it is, and
# what reads it reads the caller's repr: defined() over an undef one said
# yes, from the callee node's Unknown stamp.
for my $case (
    [ q{sub f { my ($a) = @_; return defined($a) ? "d" : "u" } print f(1), f(undef), "\n";}, "du\n", 'defined over an argument' ],
    [ q{sub f { my ($a) = @_; return $a // "u" } print f(7), f(undef), "\n";}, "7u\n", '// over an argument' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    ok(defined $got ? $got eq $want : $@ =~ /^(?:load|lower): /,
        "$name: refused, or perl's answer")
        or diag defined $got ? "got: $got" : $@;
}

done_testing;
