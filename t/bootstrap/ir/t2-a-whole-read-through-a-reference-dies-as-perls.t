# ABOUTME: `@$a > 0`, `my %c = %$h` of no such reference: perl's die under strict refs (B::SoN names the
# ABOUTME: site), an empty read without -- not a stop, and not a silent empty read under strict.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

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

# lower($src) -> (ll or undef, the .pl, why): through T2 alone
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

# as_perl([src, name], ...): each through T2 alone, its output, message and exit code perl's.
sub as_perl (@cases) {
    for my $case (@cases) {
        my ($src, $name) = @$case;
        my ($ll, $pl, $why) = lower($src);
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
}

my $w = q{my $r = eval { f(undef) }; print "caught: $@"; $r = eval { f({}) }; print "caught: $@"; $r = eval { f("zz") }; print "caught: $@";};
as_perl(
    [ q{use strict; sub f { my ($c) = @_; my $a = $c->{a}; return @$a > 0 ? "y" : "n" } print f({a => [1]}), f({a => []}), "\n"; print f({}), "\n";}, 'a count of an undef under strict refs: its die' ],
    [ q{sub f { my ($c) = @_; my $a = $c->{a}; return @$a > 0 ? "y" : "n" } print f({a => [1]}), f({}), "\n";}, 'without strict refs: empty' ],
    [ q{sub f { my ($c) = @_; my ($name, $base); my $k = 0; while ($k++ < 5) { if (ref $c eq 'HASH') { $name = $c->{n}; my $a = $c->{a}; $base = $a->[0] if @$a > 0; last } $c = { n => "x", a => [] } } return ($name // 'u') . ($base // 'u') } print f({ n => "e", a => ["b"] }), f(1), "\n";}, 'pvm c221' ],
    [ q{use strict; sub f { my ($c) = @_; my @l = @{$c->{a}}; return "@l" } print f({a => [1, 2]}), "\n"; my $r = eval { f({}) }; print "caught: $@"; print "end\n";}, 'a copy of an element\'s array, in an eval' ],
    [ q{use strict; sub f { my ($c) = @_; my $s = $c->{a}; return "[@$s]" } print f({a => [1, 2]}), "\n"; print f({a => "a very long string that goes on and on and on"}), "\n";}, 'a long string under strict refs: its die' ],
    [ qq{use strict; sub f { my (\$a) = \@_; my \@c = \@\$a; return scalar(\@c) . "\@c" } print f([1]), "\\n"; $w}, 'a copy of an argument\'s array' ],
    [ qq{use strict; sub f { my (\$a) = \@_; return join ",", sort \@\$a } print f([2, 1]), "\\n"; $w}, 'sorted' ],
    [ qq{use strict; sub f { my (\$a) = \@_; if (\@\$a) { return "y" } return "n" } print f([2, 1]), f([]), "\\n"; $w}, 'as a truth' ],
    [ q{use strict; sub f { my ($c) = @_; my %h = %{$c->{a}}; return join ",", sort keys %h } print f({a => {x => 1}}), "\n"; my $r = eval { f({}) }; print "caught: $@";}, 'a hash copied whole' ],
    [ q{use strict; sub f { my ($c) = @_; my $h = $c->{a}; return %$h ? "y" : "n" } print f({a => {x => 1}}), f({a => {}}), "\n"; my $r = eval { f({}) }; print "caught: $@";}, 'a hash as a truth' ],
    [ qq{use strict; sub f { my (\$h) = \@_; my \@l = %\$h; return scalar(\@l) } print f({a=>1}), "\\n"; $w}, "a hash's pairs" ],
    [ q{sub f { my ($c) = @_; my %h = %{$c->{a}}; return join ",", sort keys %h } print f({a => {x => 1}}), f({}), "|\n";}, 'a hash without strict refs: empty' ],
);
# WITHOUT STRICT REFS A COUNT OF AN UNDEF IS UNDEF, not 0: read as a string, it shows.
as_perl(
    [ q{sub f { my ($a) = @_; return scalar(@$a) . "|" } print f([2, 1]), f(undef), "\n";}, 'a count of an undef without strict refs, as a string: empty' ],
    [ q{sub f { my ($a) = @_; my $n = @$a; return defined $n ? "d$n" : "u" } print f([2]), f(undef), "\n";}, 'and undefined' ],
);
done_testing;
