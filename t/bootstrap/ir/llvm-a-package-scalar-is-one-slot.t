# ABOUTME: A package scalar stored through memory (EntryWrite) is one %Slot global,
# ABOUTME: boxed on store and read at its version: B::SoN -> chalk -> lli == perl.
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

# EntryWrite WAS NOT LOWERED -- the commonest refusal in the pvm corpus (20
# cases). A package scalar is SSA where the producer can bind it (Part H6);
# what reaches EntryWrite is a variable another graph sees, so it is stored.
# The storage holds a VALUE, not one typed family per representation (Part
# H5): one %Slot global per qualified name, undef until written.
for my $case (
    [ q{$::x = 1; print $::x, "\n"; $::x = $::x + 2; print $::x, "\n";}, "1\n3\n", 'a store, a read, a store from the read' ],
    [ q{our $g = 1; $g = "hi"; print "$g\n";}, "hi\n", 'an Int then a Str (Part H4)' ],
    [ q{our $g = 1; sub f { $g = $g + 1 } f(); f(); print "$g\n";}, "3\n", 'a sub stores it' ],
    [ q{our $g = "a"; sub f { return $g } $g = 2.5; print f(), "\n";}, "2.5\n", 'a sub reads it after a store' ],
    [ q{$x = 0; while ($x != 3) { $x = $x + 1; } print "ok $x\n";}, "ok 3\n", 'stored in a loop' ],
    [ q{sub f { $main::c = $main::c + 1 } f(); f(); print "$main::c\n";}, "2\n", 'never declared, counted from undef' ],
    [ q{print defined($::u) ? "d" : "u", "\n";}, "u\n", 'never written is undef' ],
    [ q{our $g = 5; sub f { return $g * 2 } print f(), "\n";}, "10\n", 'a sub reads it' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
