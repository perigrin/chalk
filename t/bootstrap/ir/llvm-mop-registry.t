# ABOUTME: Tests that the LLVM backend builds its class registry from a sealed Chalk::MOP.
# ABOUTME: Verifies method, empty-class, and :param-field programs lower and run via lli==perl.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::MOP;
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
# Test 1: method-simple via the MOP registry
# Greeter class with one method returning 42.
# (Intent-rewrite: this file previously exercised the ClassInfo bridge —
# metadata riding the graph as Call inputs. The registry is now built from
# the sealed MOP and Call nodes carry class_name instead.)
# ---------------------------------------------------------------------------

subtest 'method-simple via MOP registry: $g->greet => 42 (Int)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Method body
    my $body42 = $f->make('Constant', value => 42, const_type => 'integer');
    $body42->set_representation('Int');

    # MOP: class Greeter { method greet { return 42 } }
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Greeter');
    my $m   = $cls->declare_method('greet', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body42]));
    $mop->seal;

    # New: class structure is registry context, not an input
    my $new_g = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Greeter',
        param_names => [],
        inputs      => [],
    );
    $new_g->set_representation('Object');

    # Call(dispatch_kind='method'): resolved by class_name
    my $result = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'greet',
        class_name    => 'Greeter',
        inputs        => [$new_g],
    );
    $result->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop) };
    ok(!$@, "lowering + lli via MOP registry succeeded: $@") or do {
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
# Test 2: class-simple via the MOP registry (empty class, ref() => class name)
# ---------------------------------------------------------------------------

subtest 'class-simple via MOP registry: ref($e) => "Empty" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $mop = Chalk::MOP->new;
    $mop->declare_class('Empty');
    $mop->seal;

    my $new_e = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Empty',
        param_names => [],
        inputs      => [],
    );
    $new_e->set_representation('Object');

    my $ref_result = $f->make('Ref',
        inputs => [$new_e],
    );
    $ref_result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$ref_result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop) };
    ok(!$@, "lowering + lli via MOP registry (empty class) succeeded: $@") or do {
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
# Test 3: field-basic via the MOP registry (Str :param field + method)
# ---------------------------------------------------------------------------

subtest 'field-basic via MOP registry: $a->name => "cat" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # FieldAccess: load field[0] from $self
    my $field_read = $f->make('FieldAccess',
        field_index => 0,
        field_stash => 'Animal',
        inputs      => [],
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

    my $name_val = $f->make('Constant', value => 'cat', const_type => 'string');
    $name_val->set_representation('Str');

    my $new_a = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Animal',
        param_names => ['name'],
        inputs      => [$name_val],
    );
    $new_a->set_representation('Object');

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
    ok(!$@, "lowering + lli via MOP registry (Str field) succeeded: $@") or do {
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
