# ABOUTME: End-to-end void method call in a runtime-conditional branch arm:
# ABOUTME: `$c->inc if $x>3` must execute the call when taken (lli == perl).

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

skip_all "perl5-son not found" unless -f "$SON/B/SoN.pm";
skip_all "lli not found"       unless -x $LLI;
skip_all "perl 5.42 not found" unless -x $PERL;

use lib 'lib', 't/lib';
require Chalk::IR::Serialize::JSON;
require Chalk::Target::LLVM;

# Drive class decls + a main::corpus_case sub through B::SoN (package=main) ->
# Chalk load -> LLVM lower -> lli. Returns ('value',$out)/('gap',$e)/('err',$m).
sub lower_and_run ($program) {
    my ( $fh, $tmp ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $program;
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return ( 'err', 'no JSON' ) unless $json =~ /\S/;
    my ( $graphs, $mop ) = Chalk::IR::Serialize::JSON::from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return ( 'err', 'no graph' );
    my $ll = eval {
        Chalk::Target::LLVM->lower( $g->returns->[0],
            ( defined $mop ? ( mop => $mop ) : () ) );
    };
    return ( 'gap', $@ ) if $@;
    my ( $lfh, $lltmp ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
    print $lfh $ll;
    close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    chomp $out;
    return ( 'value', $out );
}

# The same program under real perl (calling corpus_case) as the oracle.
sub perl_val ($program) {
    my ( $fh, $tmp ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $program,
      qq{\nmy \$r = main::corpus_case();\n}
      . qq{print "Int:\$r";\n};
    close $fh;
    my $out = qx($PERL $tmp 2>&1);
    chomp $out;
    return $out;
}

my $HEAD = <<'PL';
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n = $n + 1 }
    method val { return $n }
}
package main;
PL

# label, corpus_case body, expected int
my @CASES = (
    [ 'postfix-if taken     (x=5>3 -> 11)',
      'my $c = Counter->new(n => 10); my $x = 5; $c->inc if $x > 3; $c->val', 11 ],
    [ 'postfix-if not-taken (x=2>3 -> 10)',
      'my $c = Counter->new(n => 10); my $x = 2; $c->inc if $x > 3; $c->val', 10 ],
    [ 'block-if taken       (x=5>3 -> 11)',
      'my $c = Counter->new(n => 10); my $x = 5; if ($x > 3) { $c->inc } $c->val', 11 ],
    [ 'block-if not-taken   (x=2>3 -> 10)',
      'my $c = Counter->new(n => 10); my $x = 2; if ($x > 3) { $c->inc } $c->val', 10 ],
    [ 'postfix-unless taken (x=2, unless x>3 -> 11)',
      'my $c = Counter->new(n => 10); my $x = 2; $c->inc unless $x > 3; $c->val', 11 ],
    [ 'postfix-unless not   (x=5, unless x>3 -> 10)',
      'my $c = Counter->new(n => 10); my $x = 5; $c->inc unless $x > 3; $c->val', 10 ],
    [ 'two-call arm taken   (x=5>3 -> 12)',
      'my $c = Counter->new(n => 10); my $x = 5; if ($x > 3) { $c->inc; $c->inc } $c->val', 12 ],
);

for my $case (@CASES) {
    my ( $label, $body, $want ) = @$case;
    my $prog = $HEAD . qq{sub corpus_case { $body }\n};
    subtest $label => sub {
        my ( $kind, $out ) = lower_and_run($prog);
        is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
        is( $out, "Int:$want", "lli returns $want" );
        is( $out, perl_val($prog), 'lli == perl' );
    };
}

done_testing;
