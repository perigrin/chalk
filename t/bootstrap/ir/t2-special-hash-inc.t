# ABOUTME: strict and warnings are built in (a require of one always succeeds, loads nothing); %INC
# ABOUTME: is a container whose metaobject (Chalk::Impl::INC) answers from the module registry.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

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

sub lli ($ll) {
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    return run("timeout 20 $LLI $llp");
}

for my $case (
    [ q{require strict; print "loaded ", ($INC{"strict.pm"} ? "yes" : "no"), "\n";}, 'a require of strict: built in, and in %INC' ],
    [ q{my $m = "warnings.pm"; require $m; print "loaded ", ($INC{$m} ? "yes" : "no"), "\n";}, 'a require of warnings by a constant name' ],
    [ q{my $r = require warnings; print $r, exists $INC{"warnings.pm"} ? "y" : "n", "\n";}, 'require is true; exists answers from the registry' ],
    [ q{use strict; print $INC{"strict.pm"} ? "y" : "n", "\n";}, 'a module the program used is in %INC' ],
    [ q{print tied(%INC) ? "t" : "u", $INC{"strict.pm"} ? "s" : "-", "\n"; require strict; print defined $INC{"strict.pm"} ? "d" : "u", "\n";},
      '%INC is no tie; a registry of pragmas alone is whole: strict entered by its require only' ],
    [ q{use POSIX (); print exists $INC{"Fcntl.pm"} ? "y" : "n", "\n";}, 'a key a followed module may have loaded: stopped' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $why, $pl) = t2($src);
    ok(defined $ll, "$name: lowered through T2") or diag $why;
    next unless defined $ll;
    my $got  = lli($ll);
    my $want = run("$^X $pl");
    # (a key the registry cannot answer stops by name)
    if ($name =~ /stopped\z/) {
        is($got->[2], 255, "$name");
        like($got->[1], qr/chalk: refused at run time: whether Fcntl\.pm is in %INC/, "$name: by name");
        next;
    }
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# THE VALUE is a path, perl's file system's: read as anything but a truth, refused.
{
    my ($ll, $why) = t2(q{require strict; print $INC{"strict.pm"}, "\n";});
    ok(!defined $ll, 'a value of %INC printed: not lowered');
    like($why // '', qr/a value of %INC read as other than a truth/, '... refused by name');
}

# A STORE OR A DELETE fakes a load: stopped by name.
for my $src (q{$INC{"Foo.pm"} = 1; print "x\n";}, q{require strict; delete $INC{"strict.pm"}; print "x\n";}) {
    my ($ll, $why) = t2($src);
    ok(defined $ll, "lowered: $src") or diag $why;
    next unless defined $ll;
    my $got = lli($ll);
    is($got->[2], 255, "stopped: $src");
    like($got->[1], qr/chalk: refused at run time: a (?:store into|delete from) %INC/, "by name: $src");
}

# A require of a module neither built in nor compiled in stays refused.
{
    my ($ll, $why) = t2(q{require Data::Dumper; print "x\n";});
    ok(!defined $ll, 'a require of a module not compiled in: not lowered');
}

done_testing;
