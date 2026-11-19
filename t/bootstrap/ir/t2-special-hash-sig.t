# ABOUTME: %SIG is a container whose metaobject is a MOP object (Chalk::Impl::SIG), not a tie:
# ABOUTME: its handlers stored and fetched through it, warn and die asking it, tied() false.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

# t2($src) -> (the .ll T2 made, or undef; why not)
sub t2 ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return ( undef, $err ) if $err;
    my $u = $units->[0];
    return ( $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef, $u->{path_why} // $u->{err}, $pl );
}

for my $case (
    [ q{local $SIG{__WARN__} = sub { print "caught: $_[0]" }; warn "w\n"; print "after\n";},
      'a __WARN__ handler is called with the message' ],
    [ q{sub f { local $SIG{__WARN__} = sub { print "in: $_[0]" }; warn "a\n"; return 1 } f(); warn "b\n"; print "done\n";},
      'a local __WARN__ handler is put back where its scope ends' ],
    [ q{warn "plain\n"; print "out\n";},
      'warn with no handler writes to STDERR' ],
    [ q{print tied(%SIG) ? "t" : "u", "\n";},
      '%SIG is no tie: tied is false' ],
    [ q{$SIG{USR1} = "IGNORE"; print $SIG{USR1}, "\n"; $SIG{__WARN__} = sub { 1 }; print ref($SIG{__WARN__}), exists $SIG{__WARN__} ? "y" : "n"; delete $SIG{__WARN__}; print exists $SIG{__WARN__} ? "y" : "n", "\n";},
      'a key stored, fetched, tested and deleted' ],
    [ q{$SIG{__WARN__} = sub { print "h1: $_[0]"; }; warn "one\n"; $SIG{__WARN__} = "DEFAULT"; warn "two\n"; print "end\n";},
      'DEFAULT is no handler: warn writes to STDERR' ],
    [ q{local $SIG{__DIE__} = sub { print "dying: $_[0]" }; my $ok = eval { die "boom\n"; 1 }; print "caught: $@";},
      'a __DIE__ handler is called inside an eval, then the die is caught' ],
    [ q{local $SIG{__DIE__} = sub { die "replaced\n" }; eval { die "boom\n" }; print "got: $@";},
      'a __DIE__ handler that dies: its message is the one caught' ],
    [ q{local $SIG{__DIE__} = sub { print STDOUT "last words: $_[0]" }; die "fatal\n";},
      'a __DIE__ handler, then the die is uncaught' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $why, $pl) = t2($src);
    ok(defined $ll, "$name: lowered through T2") or diag $why;
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# A program that never touches %SIG links no Chalk::Impl::SIG; one that does, links it.
{
    require Chalk::Impl;
    my $wire = sub ($src) {
        my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
        print $fh $src; close $fh;
        return scalar qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    };
    my $plain = $wire->(q{print "hi\n";});
    is(Chalk::Impl::link_json($plain), $plain, 'a program without %SIG links nothing');
    like(Chalk::Impl::link_json( $wire->(q{$SIG{USR1} = "IGNORE";}) ), qr/Chalk::Impl::SIG::FETCH/, 'one with %SIG links Chalk::Impl::SIG');
}

# A WARN INSIDE AN EXPRESSION is on the control chain (B::SoN places it as
# print), and a message not ending in a newline gets the file and line B::SoN
# gives the warn, as a die's: each runs where perl runs it, says what perl says.
for my $case (
    [ q{local $SIG{__WARN__} = sub { print "h: $_[0]" }; my $x = warn "a\n"; print "b\n"; print $x, "\n";},
      'a warn whose value is stored runs where it stands' ],
    [ q{my $n = 0; local $SIG{__WARN__} = sub { $n++ }; my @g = (warn "a\n", "b"); my @c = (warn("a\n"), "b"); print scalar(@g), scalar(@c), " $n\n";},
      'warns inside lists call the handler before the count is read' ],
    [ q{local $SIG{__WARN__} = sub { print "got: $_[0]" }; warn "no newline"; print "x\n";},
      'a message without a newline names its file and line' ],
    [ qq{print "a\\n";\n\nmy \@g = (warn("no", "newline"), 1);\nprint scalar(\@g), "\\n";},
      'with no handler, file and line on STDERR' ],
    [ q{sub f { warn "in f" } local $SIG{__WARN__} = sub { print "h: $_[0]" }; my $r = f(); print "r=$r\n";},
      "a sub's last-statement warn names its own line" ],
) {
    my ($src, $name) = $case->@*;
    my ($ll, $why, $pl) = t2($src);
    ok(defined $ll, "$name: lowered through T2") or diag $why;
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# PERL'S OWN WARNINGS reach a __WARN__ handler (an argument not numeric under
# `use warnings`), and chalk raises none of them: where warnings may be on,
# %SIG is refused by name -- never a handler left uncalled.
for my $src (
    q{use warnings; my $n = 0; $SIG{__WARN__} = sub { $n++ }; my $x = "5"; my $r = $x + "3abc"; print "$r $n\n";},
    q{use v5.36; my $n = 0; $SIG{__WARN__} = sub { $n++ }; my $x = "5"; my $r = $x + "3abc"; print "$r $n\n";},
    q{$^W = 1; my $n = 0; $SIG{__WARN__} = sub { $n++ }; my $x = "5"; my $r = $x + "3abc"; print "$r $n\n";},
) {
    my ($ll, $why) = t2($src);
    ok(!defined $ll, "perl may warn of its own: not lowered: $src");
    like($why // '', qr/%SIG where perl may raise warnings of its own/, '... refused by name');
}

# THE -w SWITCH (B::SoN's `dowarn`, a fact of the program) turns perl's own
# warnings on where no `use warnings` is: refused by name. -X turns every one
# off, `use warnings` too: then perl raises none, and the handler is lowered.
{
    my ($ll, $why) = t2(qq{#!perl -w\nmy \$n = 0; \$SIG{__WARN__} = sub { \$n++ }; my \$x = "5"; my \$r = \$x + "3abc"; print "\$r \$n\\n";\n});
    ok(!defined $ll, '#!perl -w: not lowered');
    like($why // '', qr/%SIG where perl may raise warnings of its own \(-w or \$\^W\)/, '... refused by name');
}
{
    my ($ll, $why) = t2(qq{#!perl -W\nno warnings; my \$n = 0; \$SIG{__WARN__} = sub { \$n++ }; my \$x = "5"; my \$r = \$x + "3abc"; print "\$r \$n\\n";\n});
    ok(!defined $ll, '#!perl -W under no warnings: not lowered');
    like($why // '', qr/%SIG where perl may raise warnings of its own \(-W\)/, '... refused by name');
}
{
    my $src = qq{#!perl -X\nuse warnings; my \$n = 0; \$SIG{__WARN__} = sub { \$n++ }; my \$x = "5"; my \$r = \$x + "3abc"; warn "w\\n"; print "\$r \$n\\n";\n};
    my ($ll, $why, $pl) = t2($src);
    ok(defined $ll, '#!perl -X: perl raises none of its own, lowered') or diag $why;
    if (defined $ll) {
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $ll; close $lf;
        is(run("timeout 20 $LLI $llp")->[0], run("$^X $pl")->[0], "#!perl -X: perl's output");
    }
}

# A HANDLER THAT DOES NOTHING (`sub { }`, pvm adjacency-07_subroutines:1)
# makes perl's own warnings, called or not, no different: lowered where
# warnings are on. One that does something stays refused (above).
for my $src (
    q{use v5.36; local $SIG{__WARN__} = sub { }; my @g = (warn "a", "b"); my $r = "5" + "3abc"; print scalar(@g), " $r\n";},
    q{use warnings; $SIG{__WARN__} = sub { }; my $r = "5" + "3abc"; print "$r\n";},
) {
    my ($ll, $why, $pl) = t2($src);
    ok(defined $ll, "a handler that does nothing: lowered: $src") or diag $why;
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "... perl's output");
    is($got->[2], $want->[2], "... perl's exit code");
}
# ...but not where another handler may be stored, or the one stored is code
# that runs, or something runs before the store: perl's own warning there
# goes to STDERR (no handler yet), and chalk raises none.
for my $src (
    q{use v5.36; my $x; print "$x"; $SIG{__WARN__} = sub { }; print "\n";},
    q{use warnings; my $r = "5" + "3abc"; print "$r\n"; $SIG{__WARN__} = sub { }; print "x\n";},
    q{use warnings; sub f { $SIG{__WARN__} = sub { } } f(); my $r = "5" + "3abc"; print "$r\n";},
    q{use warnings; my $n = 0; $SIG{__WARN__} = sub { }; $SIG{__WARN__} = sub { $n++ } if @ARGV == 0; my $r = "5" + "3abc"; print "$r $n\n";},
    q{use warnings; my $k = "__WARN__"; $SIG{$k} = sub { print "h\n" }; my $r = "5" + "3abc"; print "$r\n";},
    q{use warnings; $SIG{__WARN__} = sub { }; my $s = \%SIG; $s->{__WARN__} = sub { print "h: $_[0]" }; my $r = "5" + "3abc"; print "$r\n";},
) {
    my ($ll, $why) = t2($src);
    ok(!defined $ll, "a handler that may do something: not lowered: $src");
    like($why // '', qr/%SIG where perl may raise warnings of its own/, '... refused by name');
}

# A WIRE THAT DOES NOT SAY perl's warning switches (an older B::SoN): %SIG
# is refused by name, never guessed.
{
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh q{$SIG{__WARN__} = sub { print "h: $_[0]" }; warn "a\n";}; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    require JSON::PP;
    my $d = JSON::PP->new->decode($json);
    ok(exists $d->{dowarn}, 'B::SoN says the switches');
    delete $d->{dowarn};
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail(JSON::PP->new->encode($d), $select, program_mode => 1);
    my $u = ( $units // [] )->[0] // {};
    ok(!( $u->{ok} && ( $u->{path} // '' ) eq 't2' ), 'a wire without them: not lowered by T2');
    like($err // $u->{path_why} // $u->{err} // '', qr/does not say perl's warning switches/, '... refused by name');
}

done_testing;
