# ABOUTME: Tests for LLVM lowering of ClassInfo-carried graphs (Phase 4.0b).
# ABOUTME: Verifies the LLVM backend can consume ClassInfo/MethodInfo/MOP::Field in place of ClassDecl.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::MOP::Field;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::TypeTag;

my $P   = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

sub perl_oracle {
    my ($src) = @_;
    my $tag = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    my $prog = "use 5.42.0; use utf8;\nmy \$_result = do { $src };\n$tag\n";
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog;
    close $fh;
    my $out = qx($P $f 2>&1);
    my $exit = $? >> 8;
    die "perl oracle failed (exit $exit): $out" if $exit;
    chomp $out;
    return $out;
}

sub lli_run {
    my ($ret_node) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret_node);
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx($LLI $f 2>&1);
    my $exit = $? >> 8;
    die "lli failed (exit $exit): $out" if $exit;
    chomp $out;
    return ($out, $ll);
}

# ---------------------------------------------------------------------------
# Test 1: method-simple with ClassInfo (phase 4.0b)
# Greeter class with one method returning 42.
# The New node carries ClassInfo as inputs[0] instead of ClassDecl.
# ---------------------------------------------------------------------------

subtest 'method-simple with ClassInfo: $g->greet => 42 (Int)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Method body
    my $body42 = $f->make('Constant', value => 42, const_type => 'integer');
    $body42->set_representation('Int');

    # Build MethodInfo (canonical)
    my $mi = Chalk::IR::MethodInfo->new(
        name        => 'greet',
        body        => [],
        body_node   => $body42,
        return_repr => 'Int',
    );

    # Build ClassInfo (canonical)
    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Greeter',
        methods => [$mi],
        fields  => [],
    );

    # New: ClassInfo as inputs[0]
    my $new_g = $f->make('New',
        param_names => [],
        inputs      => [$ci],
    );
    $new_g->set_representation('Object');

    # MethodCall: ClassInfo as inputs[1]
    my $result = $f->make('MethodCall',
        method_name => 'greet',
        inputs      => [$new_g, $ci],
    );
    $result->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    # This SHOULD fail right now (LLVM scanner doesn't know about ClassInfo yet = RED)
    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "lowering + lli with ClassInfo succeeded: $@") or do {
        diag("Error: $@");
        return;
    };

    my $oracle = perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Greeter { method greet { return 42 } }
        my $g = Greeter->new;
        $g->greet
    });
    is($lli_out, $oracle, "lli==perl: $oracle");
    ok($ll_text !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl/, 'libperl-free');
};

# ---------------------------------------------------------------------------
# Test 2: class-simple with ClassInfo (empty class, ref() => class name)
# ---------------------------------------------------------------------------

subtest 'class-simple with ClassInfo: ref($e) => "Empty" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Empty',
        methods => [],
        fields  => [],
    );

    my $new_e = $f->make('New',
        param_names => [],
        inputs      => [$ci],
    );
    $new_e->set_representation('Object');

    my $ref_result = $f->make('Ref',
        inputs => [$new_e],
    );
    $ref_result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$ref_result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "lowering + lli with ClassInfo (empty class) succeeded: $@") or do {
        diag("Error: $@");
        return;
    };

    my $oracle = perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Empty { }
        my $e = Empty->new;
        ref($e)
    });
    is($lli_out, $oracle, "lli==perl: $oracle");
};

# ---------------------------------------------------------------------------
# Test 3: field-basic with ClassInfo + MOP::Field (Str field, :reader method)
# ---------------------------------------------------------------------------

subtest 'field-basic with ClassInfo: $a->name => "cat" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # FieldAccess: load field[0] from $self
    my $field_read = $f->make('FieldAccess',
        field_index => 0,
        field_stash => 'Animal',
        inputs      => [],
    );
    $field_read->set_representation('Str');

    # MethodInfo for the 'name' method
    my $mi = Chalk::IR::MethodInfo->new(
        name        => 'name',
        body        => [],
        body_node   => $field_read,
        return_repr => 'Str',
    );

    # MOP::Field for $name :param
    my $mf = Chalk::MOP::Field->new(
        name       => 'name',
        sigil      => '$',
        class      => undef,
        fieldix    => 0,
        type       => 'Str',
        attributes => [':param'],
    );

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Animal',
        methods => [$mi],
        fields  => [$mf],
    );

    my $name_val = $f->make('Constant', value => 'cat', const_type => 'string');
    $name_val->set_representation('Str');

    my $new_a = $f->make('New',
        param_names => ['name'],
        inputs      => [$ci, $name_val],
    );
    $new_a->set_representation('Object');

    my $result = $f->make('MethodCall',
        method_name => 'name',
        inputs      => [$new_a, $ci],
    );
    $result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "lowering + lli with ClassInfo (Str field) succeeded: $@") or do {
        diag("Error: $@");
        return;
    };

    my $oracle = perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Animal {
            field $name :param;
            method name { return $name }
        }
        my $a = Animal->new(name => 'cat');
        $a->name
    });
    is($lli_out, $oracle, "lli==perl: $oracle");
};

done_testing;
