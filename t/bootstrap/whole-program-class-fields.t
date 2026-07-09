# ABOUTME: End-to-end whole-program class fields: :reader-only and ADJUST-only
# ABOUTME: fields must be extracted so field-attrs (30) and adjust (14) lower (lli == perl).

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

# Drive a full program (class decls + a main::corpus_case sub) through B::SoN
# under package=main ONLY -> Chalk load -> LLVM lower -> lli. The referenced
# class's MOP comes across transitively. Returns ('value',$out)/('gap',$e).
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

# Run the same program under real perl (calling corpus_case) as the oracle.
sub perl_val ($program) {
    my ( $fh, $tmp ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $program,
      qq{\nmy \$r = main::corpus_case();\n}
      . qq{use Scalar::Util qw(looks_like_number);\n}
      . qq{print !defined \$r ? "Undef:"\n}
      . qq{    : looks_like_number(\$r) ? "Int:\$r" : "Str:\$r";\n};
    close $fh;
    my $out = qx($PERL $tmp 2>&1);
    chomp $out;
    return $out;
}

# field-attrs: a :reader-only class -- NO user method references the fields, so
# the old method-CV padname walk found 0 of 2. The initfields-optree enumeration
# must recover both fields (fieldix 0/1, :param) so left+right -> 30 lowers.
subtest 'field-attrs: :reader-only fields both extracted (left + right -> 30)' => sub {
    my $prog = <<'PL' . qq{sub corpus_case { my \$p = Pair->new(left => 10, right => 20); \$p->left + \$p->right }\n};
use feature 'class';
no warnings 'experimental::class';
class Pair {
    field $left  :param :reader;
    field $right :param :reader;
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Int:30', 'lli returns 30' );
    is( $out, perl_val($prog), 'lli == perl' );
};

# A :reader field returned directly (no arithmetic): Pair->new(...)->left -> 10.
subtest 'field-attrs: a :reader field returned directly (-> 10)' => sub {
    my $prog = <<'PL' . qq{sub corpus_case { my \$p = Pair->new(left => 10, right => 20); \$p->left }\n};
use feature 'class';
no warnings 'experimental::class';
class Pair {
    field $left  :param :reader;
    field $right :param :reader;
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Int:10', 'lli returns 10' );
    is( $out, perl_val($prog), 'lli == perl' );
};

# adjust: an ADJUST-only field ($double, not :param, no default) is written by
# the ADJUST block and read by method double. $val (:param) is referenced only
# by ADJUST, not by a user method -- so the two fields live in different CVs and
# only the full enumeration + ADJUST-CV varname recovery gets both.
subtest 'adjust: ADJUST-computed field lowers (double -> 14)' => sub {
    my $prog = <<'PL' . qq{sub corpus_case { my \$b = Box->new(val => 7); \$b->double }\n};
use feature 'class';
no warnings 'experimental::class';
class Box {
    field $val :param = 0;
    field $double;
    ADJUST { $double = $val * 2 }
    method double { $double }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Int:14', 'lli returns 14' );
    is( $out, perl_val($prog), 'lli == perl' );
};

# No over-extraction: a class with a field referenced by NO method and NO ADJUST
# (a bare, unused field) must still enumerate exactly the declared fields with
# correct indices, and must not crash the load. The used field still lowers.
subtest 'a field read by no method extracts without crashing (used field -> 5)' => sub {
    my $prog = <<'PL' . qq{sub corpus_case { my \$w = Widget->new(a => 5, b => 9); \$w->get_a }\n};
use feature 'class';
no warnings 'experimental::class';
class Widget {
    field $a :param;
    field $b :param;
    method get_a { $a }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Int:5', 'lli returns the read field -> 5' );
    is( $out, perl_val($prog), 'lli == perl' );
};

done_testing();
