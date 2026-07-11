# ABOUTME: End-to-end chained void method calls: $c->inc; $c->inc; $c->val must
# ABOUTME: accumulate the field store across calls (memory-ordered, lli == perl).

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

# Two class forms: `$n = $n + 1` (TARGMY store) and `$n += 1` (compound store).
my %FORMS = (
    'assign-form' => <<'PL',
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n = $n + 1 }
    method val { return $n }
}
package main;
PL
    'compound-form' => <<'PL',
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method inc { $n += 1 }
    method val { return $n }
}
package main;
PL
);

# (start, chained-inc count, expected val).
my @CASES = (
    [ 0, 1, 1 ],
    [ 0, 2, 2 ],
    [ 0, 3, 3 ],
    [ 5, 4, 9 ],
);

for my $form ( sort keys %FORMS ) {
    my $head = $FORMS{$form};
    for my $c (@CASES) {
        my ( $start, $incs, $want ) = @$c;
        my $chain = join ' ', map { "\$c->inc;" } 1 .. $incs;
        my $prog  = $head
          . qq{sub corpus_case { my \$c = Counter->new(n => $start); $chain \$c->val }\n};
        subtest "$form: n=$start then $incs inc -> $want" => sub {
            my ( $kind, $out ) = lower_and_run($prog);
            is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
            is( $out, "Int:$want", "lli returns $want" );
            is( $out, perl_val($prog), 'lli == perl' );
        };
    }
}

# A plain field assignment inside a method (`$name = "hi"`) is a Str store, not
# an arithmetic mutation -- it goes through the sassign FieldAccess-lvalue path,
# a distinct store site. Without it the field keeps its default (a silent
# miscompile: lli returned the default "a", perl "hi").
subtest 'str field: a plain `$name = "hi"` in a method stores back' => sub {
    my $prog = <<'PL' . qq{sub corpus_case { my \$o = Named->new(name => "a"); \$o->rename; \$o->get }\n};
use feature 'class';
no warnings 'experimental::class';
class Named {
    field $name :param = "x";
    method rename { $name = "hi" }
    method get { return $name }
}
package main;
PL
    my ( $kind, $out ) = lower_and_run($prog);
    is( $kind, 'value', 'lowered (not a GAP)' ) or diag($out);
    # perl_val's oracle is integer-tagged (Int:$r); this case is a Str, so assert
    # the lli output against the known-correct tagged value directly. perl's
    # $o->rename; $o->get returns "hi" (verified against the TypeTag oracle).
    is( $out, 'Str:hi', 'lli returns the stored Str value -> hi (== perl "hi")' );
};

done_testing;
