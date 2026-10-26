# ABOUTME: an element store through a value read by its tag -- a reference passed in, an
# ABOUTME: element that may be undef (autovivified) -- B::SoN -> chalk -> lli == perl.
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

# The container was refused whenever it was read by its tag (pvm 176 184 225
# 232 233): a reference handed in is stored through; an element that is
# undef is made an aggregate where it stands, as perl autovivifies it.
for my $c (
    [ q{sub emit { my $h = $_[0]; $h->{n} = "z"; 1 } my %x = (n => "a"); emit(\%x); print $x{n}, "\n";} ],
    [ q{sub g { $_[0][$_[1]] = $_[0][$_[1]] . "!" } my $l = [qw(a b)]; g($l, 1); print "@$l\n";} ],
    [ q{my %h = (x => {}); $h{x}{y} = 2; print join(",", keys %{ $h{x} }), "\n";} ],
    [ q{my @a; $a[0]{k} = 1; print $a[0]{k}, " ", scalar(@a), "\n";} ],
    [ q{my @a; $a[1][0] = 5; print scalar(@a), " ", $a[1][0], " ", defined $a[0] ? "d" : "u", "\n";} ],
    [ q{my %h; $h{x}{y} = 1; $h{x}{z} = 2; print join(",", sort keys %{ $h{x} }), " ", scalar(keys %h), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# AN UNDEF WITH NOWHERE TO GO -- a copy of an argument -- stops the program;
# and a store in a loop over an autovivified element is refused further on.
# Perl's answer, refused by name, or stopped: never another answer.
for my $src (
    q{sub f { my $h = $_[0]; $h->{a} = 1; 1 } my $u; f($u); print "ran\n";},
    q{my %h; for my $w (qw(a b a)) { $h{$w}{n}++ } print join(",", map { "$_$h{$_}{n}" } sort keys %h), "\n";},
) {
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:|LLVM backend:|lli exited 255/, "refused or stopped: $src") }
}

# A `local` STORE is put back when its scope ends; chalk does not put it back,
# and the restore is not always on the wire (pvm 176 kept the store): refused.
for my $src (
    q{sub h { join ",", sort keys %{ $_[0] } } sub f { my ($s, $n) = @_; local $s->{c} = { $n => 1 }; h($s) } my $s = { a => 1 }; print f($s, "x"), " | ", h($s), "\n";},
    q{sub h { my $s = shift; join ",", map { "$_=" . (ref $s->{$_} ? "{" . join("", sort keys %{$s->{$_}}) . "}" : $s->{$_} // "u") } sort keys %$s } sub f { my ($self, $n) = @_; local $self->{c} = { ($self->{c} // {})->%*, $n => 1 }; return h($self) } my $s = { a => 1 }; print f($s, "x"), " | ", h($s), "\n"; },
) {
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:/, "refused by name: $src") }
}

done_testing;
