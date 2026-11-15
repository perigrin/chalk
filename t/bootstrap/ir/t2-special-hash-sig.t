# ABOUTME: %SIG is a container whose metaobject is a MOP object (Chalk::Impl::SIG), not a tie:
# ABOUTME: its handlers stored and fetched through it, warn and die asking it, tied() false.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
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

# A WARN B::SoN PUTS ON NO CONTROL CHAIN (inside an expression: `my $x = warn
# ...`) runs where nothing says: refused by name, never run out of order.
{
    my ($ll, $why) = t2(q{local $SIG{__WARN__} = sub { print "h: $_[0]" }; my $x = warn "a\n"; print "b\n"; print $x, "\n";});
    ok(!defined $ll, 'a warn on no control chain: not lowered');
    like($why // '', qr/a warn B::SoN places on no control chain/, '... refused by name');
}

# A WARN'S MESSAGE NOT ENDING IN A NEWLINE names its file and line, which
# B::SoN does not give a warn: refused by name, never printed without them.
{
    my ($ll, $why) = t2(q{local $SIG{__WARN__} = sub { print "got: $_[0]" }; warn "no newline"; print "x\n";});
    ok(!defined $ll, 'a warn whose message may lack its file and line: not lowered');
    like($why // '', qr/a warn whose message may not end in a newline/, '... refused by name');
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

done_testing;
