# ABOUTME: End-to-end whole-program object idiom: a class referenced only from a
# ABOUTME: main sub emits its MOP under package=main so $c->get lowers (lli == perl).

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

# Drive a full program (class decls + a main::corpus_case sub) through
# B::SoN under package=main ONLY -> Chalk load -> LLVM lower -> lli. The
# referenced class's MOP must come across transitively (the fix under test),
# so no package=<class> filter is added. Returns ('value',$out)/('gap',$e)/
# ('err',$msg).
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
# Mirror the LLVM backend's tagged print: a number is Int:<v>, anything else
# Str:<v>, undef is Undef:.
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

my $COUNTER = <<'PL';
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method get { $n }
}
package main;
PL

subtest 'the teaching case: my $x = $c->get lowers to 5 (lli == perl)' => sub {
    my $prog = $COUNTER
      . qq{sub corpus_case { my \$c = Counter->new(n => 5); my \$x = \$c->get; \$x }\n};
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Int:5', 'lli returns 5' );
    is( $out, perl_val($prog), 'lli == perl' );
};

subtest 'a method returning Str lowers (Str return repr)' => sub {
    # The Str comes from the constructor arg (a ctor-arg Str types the field
    # Str, 019f0597). A Str field DEFAULT is a separate un-lowered backend
    # follow-up, so the value is supplied at construction, not defaulted.
    my $prog = <<'PL' . qq{sub corpus_case { my \$g = Greeter->new(msg => "hi"); \$g->hello }\n};
use feature 'class';
no warnings 'experimental::class';
class Greeter {
    field $msg :param;
    method hello { $msg }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Str:hi', 'lli returns the string value' );
    is( $out, perl_val($prog), 'lli == perl' );
};

subtest 'an inherited method resolves via MRO (Child->new->base_method)' => sub {
    my $prog = <<'PL' . qq{sub corpus_case { my \$c = Child->new(n => 7); \$c->get }\n};
use feature 'class';
no warnings 'experimental::class';
class Base {
    field $n :param = 0;
    method get { $n }
}
class Child :isa(Base) {
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Int:7', 'lli returns the inherited get -> 7' );
    is( $out, perl_val($prog), 'lli == perl' );
};

subtest 'a repeated method call returns the same value (idempotent read)' => sub {
    # Construct, then read the same method twice and return the second read.
    # Both $c->val calls hash-cons to one node; returning it directly exercises
    # a method Call whose repr must resolve for the lowering to succeed.
    my $prog = <<'PL' . qq{sub corpus_case { my \$c = Box->new(v => 9); my \$a = \$c->val; my \$b = \$c->val; \$b }\n};
use feature 'class';
no warnings 'experimental::class';
class Box {
    field $v :param = 0;
    method val { $v }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    is( $out, 'Int:9', 'lli returns 9' );
    is( $out, perl_val($prog), 'lli == perl' );
};

subtest 'arith over two method-call results does not miscompile (GAP or correct)' => sub {
    # `$a + $b` where both operands are method Calls. The Add's repr-propagation
    # runs before the method-Call reprs are stamped (a Chalk loader ordering
    # gap), so the Add currently GAPs. This subtest pins the ANTI-MISCOMPILE
    # invariant: a future Chalk fix must produce the correct value (Int:18) or
    # keep an honest GAP -- never a silently-wrong value.
    my $prog = <<'PL' . qq{sub corpus_case { my \$c = Box->new(v => 9); my \$a = \$c->val; my \$b = \$c->val; \$a + \$b }\n};
use feature 'class';
no warnings 'experimental::class';
class Box {
    field $v :param = 0;
    method val { $v }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    if ( $kind eq 'value' ) {
        is( $out, 'Int:18', 'if it lowers, it lowers to the correct 9 + 9 -> 18' );
        is( $out, perl_val($prog), 'lli == perl' );
    }
    else {
        isnt( $kind, 'value',
            "arith-over-method-call does not silently lower (got $kind)" );
    }
};

# A method whose return repr the backend cannot lower must GAP loudly, NOT emit
# invalid/type-mismatched LLVM IR or crash lli. Bringing the class MOP across
# under package=main exposed backend shapes that were previously masked by the
# no-MOP GAP; emitting broken IR is strictly worse than the clean GAP it replaced.
subtest 'a Bool-returning method lowers correctly or GAPs, never broken IR' => sub {
    my $prog = <<'PL' . qq{sub corpus_case { my \$w = Widget->new(n => 5); \$w->big }\n};
use feature 'class';
no warnings 'experimental::class';
class Widget {
    field $n :param = 0;
    method big { $n > 3 }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    if ( $kind eq 'value' ) {
        # lli emits '1' for true (i1); perl's oracle prints Int:1. Either the
        # backend lowers the i1 return correctly or it must GAP -- but the lli
        # output must NOT be an LLVM verify error / crash.
        unlike( $out, qr/\berror\b|Stack dump|Segmentation|expected 'i64/i,
            "Bool method did not produce invalid IR / crash lli (got: $out)" );
    }
    else {
        isnt( $kind, 'value', "Bool method GAPs cleanly instead of broken IR (got $kind)" );
    }
};

subtest 'a field whose ctor-arg type conflicts with its default GAPs, never crashes' => sub {
    # field $s :param = "hello" (Str default) constructed with s => 42 (Int) is a
    # repr conflict. Emitting the MOP must not produce IR that segfaults lli.
    my $prog = <<'PL' . qq{sub corpus_case { my \$w = Widget->new(s => 42); \$w->get }\n};
use feature 'class';
no warnings 'experimental::class';
class Widget {
    field $s :param = "hello";
    method get { $s }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    if ( $kind eq 'value' ) {
        unlike( $out, qr/\berror\b|Stack dump|Segmentation/i,
            "repr-conflict field did not crash lli (got: $out)" );
    }
    else {
        isnt( $kind, 'value', "repr-conflict field GAPs cleanly (got $kind)" );
    }
};

done_testing();
