# ABOUTME: an arm that dies never reaches the merge, so its value is no phi entry:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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

# THE EXIT MERGE OF `if ... return; elsif ... return; else die` has the die's
# Unwind as one Region input. Its phi took an entry from the aborting block,
# which never branches to the merge: lli, "PHINode should have one entry for
# each predecessor of its parent basic block!".
for my $case (
    [ q{sub k { my $r = shift; if ($r eq 'a') { return "A$r" } elsif ($r eq 'b') { return "B$r" } else { die "no $r\n" } }
        my $x = k('a'); my $y = k('b'); print "$x $y\n";}, "Aa Bb\n", 'if/elsif returns, else dies' ],
    [ q{sub k { my $r = shift; if ($r eq 'z') { die "no $r\n" } return "A$r" }
        my $x = k('a'); print "$x\n";}, "Aa\n", 'the then arm dies' ],
    [ q{sub k { my $r = shift; return "A$r" if $r eq 'a'; die "no $r\n" }
        my $x = k('a'); print "$x\n";}, "Aa\n", 'a guarded return, then a die' ],
    [ q{sub k { my $r = shift; if ($r eq 'a') { return "A$r" } elsif ($r eq 'b') { return "B$r" } else { if ($r eq 'c') { die "c\n" } die "no $r\n" } }
        my $x = k('a'); my $y = k('b'); print "$x $y\n";}, "Aa Bb\n", 'the else dies after an if of its own' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name") ; next }
    is($got, $want, "$name: perl's answer") or diag $@;
}

# THE DIE AFTER AN ARM'S OWN `if` ends the arm: the walk for it stopped at the
# inner If, so the arm branched on to the merge and the sub returned.
{
    my $src = q{sub k { my $r = shift; if ($r eq 'a') { return "A$r" } else { if ($r eq 'c') { die "c\n" } die "no $r\n" } }
                print k('a'), "\n"; print k('x'), "\n"; print "after\n";};
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    if (!$units->[0]{ok}) { like($units->[0]{err}, qr/GAP/, 'the die path: refused by name') }
    else {
        my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $units->[0]{ll}; close $lf;
        my $out = qx($LLI $ll 2>/dev/null);
        is($? >> 8, 255, 'the die path: exits 255, as perl does');
        is($out, "Aa\n", 'the die path: nothing after the die is printed');
    }
}

done_testing;
