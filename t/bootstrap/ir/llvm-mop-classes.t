# ABOUTME: Tests for feature-class MOP lowering: MOP::Class/Method/Field, Call(new), Call(method).
# ABOUTME: Verifies the class idioms lower correctly to LLVM IR with lli==perl (libperl-free).
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::MOP;
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
    my ($ret_node, $mop) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret_node, mop => $mop);
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

    # MOP: class Greeter { method greet { return 42 } }
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Greeter');
    my $m   = $cls->declare_method('greet', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body42]));
    $mop->seal;

    # New: Greeter->new (no :param fields)
    my $new_g = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Greeter',
        param_names => [],
        inputs      => [],
    );
    $new_g->set_representation('Object');

    # Call: $g->greet
    my $result = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'greet',
        class_name    => 'Greeter',
        inputs        => [$new_g],
    );
    $result->set_representation('Int');

    # Return node
    my $ret = $f->make_cfg('Return', inputs => [$result]);

    # Lower to LLVM IR and run
    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop) };
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
    my $mop = Chalk::MOP->new;
    $mop->declare_class('Empty');
    $mop->seal;

    my $new_e = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Empty',
        param_names => [],
        inputs      => [],
    );
    $new_e->set_representation('Object');

    # ref($obj) = load class-name from vtable slot 0
    my $ref_result = $f->make('Ref',
        inputs => [$new_e],
    );
    $ref_result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$ref_result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop) };
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

    # FieldAccess: load field[0] from $self (implicit in method body context)
    my $field_read = $f->make('FieldAccess',
        field_index  => 0,
        field_stash  => 'Animal',
        inputs       => [],
    );
    $field_read->set_representation('Str');

    # MOP: class Animal { field $name :param; method name { return $name } }
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Animal');
    $cls->declare_field('name', sigil => '$', type => 'Str',
        attributes => [':param']);
    my $m = $cls->declare_method('name', return_type => 'Str');
    $m->graph->merge($f->make_cfg('Return', inputs => [$field_read]));
    $mop->seal;

    # New: Animal->new(name => 'cat')
    my $name_val = $f->make('Constant', value => 'cat', const_type => 'string');
    $name_val->set_representation('Str');

    my $new_a = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Animal',
        param_names => ['name'],
        inputs      => [$name_val],
    );
    $new_a->set_representation('Object');

    # Call: $a->name
    my $result = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'name',
        class_name    => 'Animal',
        inputs        => [$new_a],
    );
    $result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop) };
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
# Test: Str field STORE inside a method body — Assign(FieldAccess-lvalue, Str)
#
# The field-store payload path must build a %StrPair for a Str rhs (matching the
# field READ path, which reads a Str field via inttoptr i64 -> %StrPair*). A bare
# `add i64 0, <i8*>` (the Bool/Int path) is invalid IR for a pointer rhs and would
# be read back as a corrupt StrPair. Round-trip: set a Str field, then read it.
#
#   class Tag { field $s; method set { $s = "hi" } method get { return $s } }
#   my $t = Tag->new; $t->set; $t->get   -> "hi"
# ---------------------------------------------------------------------------

subtest 'Str field store in method body: $t->set; $t->get => "hi" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # method set { $s = "hi" } — body: Assign(FieldAccess-lvalue(0,"Tag"), "hi")
    my $hi = $f->make('Constant', value => 'hi', const_type => 'string');
    $hi->set_representation('Str');
    my $fa_lv = $f->make('FieldAccess', field_index => 0, field_stash => 'Tag', inputs => []);
    $fa_lv->set_representation('Str');
    my $store = $f->make('Assign', inputs => [$fa_lv, $hi]);
    $store->set_representation('Str');

    # method get { return $s } — body: FieldAccess(0,"Tag") read
    my $fa_rd = $f->make('FieldAccess', field_index => 0, field_stash => 'Tag', inputs => []);
    $fa_rd->set_representation('Str');

    # MOP: class Tag { field $s; method set; method get }
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Tag');
    $cls->declare_field('s', sigil => '$', type => 'Str', attributes => []);
    my $m_set = $cls->declare_method('set', return_type => 'Str');
    $m_set->graph->merge($f->make_cfg('Return', inputs => [$store]));
    my $m_get = $cls->declare_method('get', return_type => 'Str');
    $m_get->graph->merge($f->make_cfg('Return', inputs => [$fa_rd]));
    $mop->seal;

    # my $t = Tag->new;
    my $new_t = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Tag', param_names => [], inputs => []);
    $new_t->set_representation('Object');

    # $t->set;  (control-position side effect, before get)
    my $set_call = $f->make('Call', dispatch_kind => 'method', name => 'set',
        class_name => 'Tag', inputs => [$new_t]);
    $set_call->set_representation('Str');

    # $t->get
    my $get_call = $f->make('Call', dispatch_kind => 'method', name => 'get',
        class_name => 'Tag', inputs => [$new_t]);
    $get_call->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$get_call]);
    $ret->set_control_in($set_call);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };

    my $oracle = eval { perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Tag { field $s; method set { $s = "hi" } method get { return $s } }
        my $t = Tag->new; $t->set; $t->get
    }) };
    is($lli_out, $oracle, "lli output matches perl oracle: $oracle");

    ok($ll_text !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        'generated .ll is libperl-free');
};

# ---------------------------------------------------------------------------
# Test: Adversarial — Call(method) on absent method MUST die loudly
# ---------------------------------------------------------------------------

subtest 'adversarial: Call(method) on absent method dies loudly at lowering' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # class Greeter has 'greet' (no 'wave' method defined)
    my $body42 = $f->make('Constant', value => 42, const_type => 'integer');
    $body42->set_representation('Int');
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Greeter');
    my $m   = $cls->declare_method('greet', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body42]));
    $mop->seal;

    my $new_g = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Greeter',
        param_names => [],
        inputs      => [],
    );
    $new_g->set_representation('Object');

    # Call 'wave' which is NOT defined — must die at lowering
    my $bad_call = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'wave',   # absent from vtable!
        class_name    => 'Greeter',
        inputs        => [$new_g],
    );
    $bad_call->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$bad_call]);

    my $died = false;
    my $error_msg = '';
    eval { Chalk::Target::LLVM->lower($ret, mop => $mop) };
    if ($@) {
        $died = true;
        $error_msg = $@;
    }

    ok($died, 'lowering dies when method is absent from vtable');
    like($error_msg, qr/wave|absent|vtable|method/i,
        'die message mentions the missing method or vtable');
};

# ---------------------------------------------------------------------------
# Test: Adversarial — Call(method) on a class the sealed MOP never declared.
# (Intent-rewrite: this previously dispatched against a methodless ClassInfo
# descriptor riding the graph; MOP-direct resolves Call.class_name against
# the sealed-MOP registry, so the equivalent is an unregistered class name.)
# ---------------------------------------------------------------------------

subtest 'adversarial: Call(method) on undeclared class dies loudly at lowering' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # KnownClass has 'foo' but UndeclaredClass is never declared in the MOP
    my $body = $f->make('Constant', value => 1, const_type => 'integer');
    $body->set_representation('Int');
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('KnownClass');
    my $m   = $cls->declare_method('foo', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body]));
    $mop->seal;

    my $new_k = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'KnownClass',
        param_names => [],
        inputs      => [],
    );
    $new_k->set_representation('Object');

    # Call on an object of KnownClass but using UndeclaredClass as the class
    # (no such class in the sealed MOP -> must die)
    my $bad_call = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'bar',
        class_name    => 'UndeclaredClass',
        inputs        => [$new_k],
    );
    $bad_call->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$bad_call]);

    my $died = false;
    eval { Chalk::Target::LLVM->lower($ret, mop => $mop) };
    if ($@) {
        $died = true;
    }

    ok($died, 'lowering dies when calling method on class with no matching method');
};

done_testing;
