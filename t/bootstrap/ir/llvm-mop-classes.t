# ABOUTME: Tests for G5 feature-class MOP lowering: ClassInfo, MethodInfo, MOP::Field, New, MethodCall.
# ABOUTME: Verifies 7 class idioms lower correctly to LLVM IR with lli==perl (libperl-free).
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

my $P = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Helper: run perl and get oracle output
sub perl_oracle {
    my ($src) = @_;
    my $tag_fragment = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    my $prog = "use 5.42.0; use utf8;\nmy \$_result = do { $src };\n$tag_fragment\n";
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

# Helper: lower a Return node to LLVM IR, run lli, return output
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
# Test 1: method-simple — class with one method returning a constant Int
# ---------------------------------------------------------------------------

subtest 'method-simple: $g->greet => 42 (Int)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Method body: greet($self) { return 42 }
    my $body42 = $f->make('Constant', value => 42, const_type => 'integer');
    $body42->set_representation('Int');

    # MethodInfo for greet
    my $mi = Chalk::IR::MethodInfo->new(
        name        => 'greet',
        body        => [],
        body_node   => $body42,
        return_repr => 'Int',
    );

    # ClassInfo for Greeter
    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Greeter',
        methods => [$mi],
        fields  => [],
    );

    # New: Greeter->new (no :param fields)
    my $new_g = $f->make('New',
        param_names => [],
        inputs      => [$ci],
    );
    $new_g->set_representation('Object');

    # MethodCall: $g->greet
    my $result = $f->make('MethodCall',
        method_name => 'greet',
        inputs      => [$new_g, $ci],
    );
    $result->set_representation('Int');

    # Return node
    my $ret = $f->make_cfg('Return', inputs => [$result]);

    # Lower to LLVM IR and run
    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };

    # lli==perl
    my $oracle = eval { perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Greeter { method greet { return 42 } }
        my $g = Greeter->new;
        $g->greet
    }) };
    is($lli_out, $oracle, "lli output matches perl oracle: $oracle");

    # libperl-free
    ok($ll_text !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        'generated .ll is libperl-free')
        or diag("Found libperl symbols in:\n$ll_text");
};

# ---------------------------------------------------------------------------
# Test 2: class-simple — empty class, ref() returns class name as Str
# ---------------------------------------------------------------------------

subtest 'class-simple: ref($e) => "Empty" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Empty class: no methods, no fields
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

    # ref($obj) = load class-name from vtable slot 0
    my $ref_result = $f->make('Ref',
        inputs => [$new_e],
    );
    $ref_result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$ref_result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };

    my $oracle = eval { perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Empty { }
        my $e = Empty->new;
        ref($e)
    }) };
    is($lli_out, $oracle, "lli output matches perl oracle: $oracle");

    ok($ll_text !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        'generated .ll is libperl-free');
};

# ---------------------------------------------------------------------------
# Test 3: field-basic — :param field + method returning field value
# ---------------------------------------------------------------------------

subtest 'field-basic: $a->name => "cat" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # MOP::Field: $name :param at index 0
    my $mf = Chalk::MOP::Field->new(
        name       => 'name',
        sigil      => '$',
        class      => undef,
        fieldix    => 0,
        type       => 'Str',
        attributes => [':param'],
    );

    # FieldAccess: load field[0] from $self (implicit in method body context)
    my $field_read = $f->make('FieldAccess',
        field_index  => 0,
        field_stash  => 'Animal',
        inputs       => [],
    );
    $field_read->set_representation('Str');

    # MethodInfo for name
    my $mi = Chalk::IR::MethodInfo->new(
        name        => 'name',
        body        => [],
        body_node   => $field_read,
        return_repr => 'Str',
    );

    # ClassInfo for Animal: methods=[mi], fields=[mf]
    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Animal',
        methods => [$mi],
        fields  => [$mf],
    );

    # New: Animal->new(name => 'cat')
    my $name_val = $f->make('Constant', value => 'cat', const_type => 'string');
    $name_val->set_representation('Str');

    my $new_a = $f->make('New',
        param_names => ['name'],
        inputs      => [$ci, $name_val],
    );
    $new_a->set_representation('Object');

    # MethodCall: $a->name
    my $result = $f->make('MethodCall',
        method_name => 'name',
        inputs      => [$new_a, $ci],
    );
    $result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };

    my $oracle = eval { perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Animal {
            field $name :param;
            method name { return $name }
        }
        my $a = Animal->new(name => 'cat');
        $a->name
    }) };
    is($lli_out, $oracle, "lli output matches perl oracle: $oracle");

    ok($ll_text !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        'generated .ll is libperl-free');
};

# ---------------------------------------------------------------------------
# Test: Adversarial — MethodCall on absent method MUST die loudly
# ---------------------------------------------------------------------------

subtest 'adversarial: MethodCall on absent method dies loudly at lowering' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # MethodInfo: greet (no 'wave' method defined)
    my $body42 = $f->make('Constant', value => 42, const_type => 'integer');
    $body42->set_representation('Int');
    my $mi = Chalk::IR::MethodInfo->new(
        name        => 'greet',
        body        => [],
        body_node   => $body42,
        return_repr => 'Int',
    );

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Greeter',
        methods => [$mi],
        fields  => [],
    );

    my $new_g = $f->make('New',
        param_names => [],
        inputs      => [$ci],
    );
    $new_g->set_representation('Object');

    # Call 'wave' which is NOT defined — must die at lowering
    my $bad_call = $f->make('MethodCall',
        method_name => 'wave',   # absent from vtable!
        inputs      => [$new_g, $ci],
    );
    $bad_call->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$bad_call]);

    my $died = false;
    my $error_msg = '';
    eval { Chalk::Target::LLVM->lower($ret) };
    if ($@) {
        $died = true;
        $error_msg = $@;
    }

    ok($died, 'lowering dies when method is absent from vtable');
    like($error_msg, qr/wave|absent|vtable|method/i,
        'die message mentions the missing method or vtable');
};

# ---------------------------------------------------------------------------
# Test: Adversarial — MethodCall on undeclared class (no ClassInfo in graph)
# ---------------------------------------------------------------------------

subtest 'adversarial: MethodCall without ClassDecl dies loudly at lowering' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # KnownClass has 'foo' but NOT 'bar'
    my $body = $f->make('Constant', value => 1, const_type => 'integer');
    $body->set_representation('Int');
    my $foo_mi = Chalk::IR::MethodInfo->new(
        name        => 'foo',
        body        => [],
        body_node   => $body,
        return_repr => 'Int',
    );
    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'KnownClass',
        methods => [$foo_mi],
        fields  => [],
    );

    my $new_k = $f->make('New',
        param_names => [],
        inputs      => [$ci],
    );
    $new_k->set_representation('Object');

    # UndeclaredClass has NO methods
    my $ci2 = Chalk::IR::ClassInfo->new(
        name    => 'UndeclaredClass',
        methods => [],
        fields  => [],
    );

    # MethodCall on an object of KnownClass but using UndeclaredClass as the descriptor
    # (no methods in UndeclaredClass -> must die)
    my $bad_call = $f->make('MethodCall',
        method_name => 'bar',
        inputs      => [$new_k, $ci2],
    );
    $bad_call->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$bad_call]);

    my $died = false;
    eval { Chalk::Target::LLVM->lower($ret) };
    if ($@) {
        $died = true;
    }

    ok($died, 'lowering dies when calling method on class with no matching method');
};

done_testing;
