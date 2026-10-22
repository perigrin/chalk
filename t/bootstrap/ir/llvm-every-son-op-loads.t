# ABOUTME: Every node op B::SoN emits loads; a program using one prints what perl
# ABOUTME: prints through lli, or is refused naming why -- never "Unknown data node operation".
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

# THIRTEEN OPS B::SoN EMITS WERE UNKNOWN TO THE LOADER, and every program using
# one died in from_json before the backend could say what it lacked (119 pvm
# corpus cases, perl5-son's tools/corpus-llvm-roundtrip.pl). Each loads now;
# what the backend cannot lower yet it refuses by name.
my @cases = (
    [ Exists             => q{my %h = (a => 1); print exists $h{a} ? "y" : "n", exists $h{b} ? "y" : "n", "\n";} ],
    [ Delete             => q{my %h = (a => 1, b => 2); delete $h{a}; print join(",", sort keys %h), "\n";} ],
    [ ElemRestore        => q{our %h = (a => 1); sub f { local $h{a} = 2; print $h{a} } f(); print $h{a}, "\n";} ],
    [ EntryWrite         => q{our $g = 1; $g = 2; print "$g\n";} ],
    [ LocalAlias         => q{sub p { print $_ } p() for (1, 2); print "\n";} ],
    [ PackageMark        => q{package Foo; print "a\n"; package main; print "ok\n";} ],
    [ Increment          => q{my $s = "az"; $s++; print "$s\n";} ],
    [ Transliterate      => q{my $s = "abc"; (my $t = $s) =~ tr/a-c/A-C/; print "$t\n";} ],
    [ TransliterateCount => q{my $s = "banana"; my $n = ($s =~ tr/a//); print "$n\n";} ],
    [ Wantarray          => q{sub w { wantarray ? "l" : "s" } my @x = w(); my $y = w(); print "$x[0]$y\n";} ],
    [ 'Chomp, ChompValue'=> q{my $s = "x\n"; my $n = chomp($s); print "$s$n\n";} ],
    [ RegexSubstCount    => q{my $s = "aaa"; my $n = ($s =~ s/a/b/g); print "$n $s\n";} ],
);
for my $case (@cases) {
    my ($op, $src) = @$case;
    my $want = do {
        my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
        print $fh $src;
        close $fh;
        scalar qx($^X $pl);
    };
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "$op: lli prints what perl prints") }
    else {
        unlike($@, qr/Unknown data node operation/, "$op: loads") or diag $@;
        like($@, qr/^(?:load|lower): .*(?:GAP|LLVM backend:)/, "$op: refused, naming why") or diag $@;
    }
}

done_testing;
