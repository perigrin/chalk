# ABOUTME: Tests individual XS codegen constructs that Tier C methods depend on.
# ABOUTME: Synthetic minimal classes exercise for-loops, push, sprintf, split, coderef invocation, isa.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# === Skip guards ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use TestXSHelpers qw(setup_xs_grammar build_and_load fork_test);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSTierCConstructTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# === Helper: parse source string -> IR ===

my sub parse_source_ir($source) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return unless defined $result;

    my $sem_ctx = $result->[4];
    return unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# ============================================================
# 1. for-loop over PostfixDeref (->@*)
# ============================================================

subtest 'for-loop over PostfixDeref' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class ForLoopDeref {
    field $items :param :reader;

    method count_items() {
        my $count = 0;
        for my $item ($items->@*) {
            $count = $count + 1;
        }
        return $count;
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::ForLoopDeref';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: PostfixDeref iteration in for-loop' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new(items => [qw(a b c)]);
        die "count_items != 3" unless $obj->count_items() == 3;
    }, 'count_items');
};

# ============================================================
# 2. push with PostfixDeref
# ============================================================

subtest 'push with PostfixDeref' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class PushDeref {
    field $items = [];

    method add_item($item) {
        push $items->@*, $item;
    }

    method item_count() {
        return scalar $items->@*;
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::PushDeref';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: push with PostfixDeref' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new();
        $obj->add_item('x');
        die "item_count != 1" unless $obj->item_count() == 1;
    }, 'add_item + item_count');
};

# ============================================================
# 3. sprintf
# ============================================================

subtest 'sprintf' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class SprintfUser {
    field $name :param :reader;
    field $count :param :reader;

    method format_string() {
        return sprintf("Name: %s, Count: %d", $name, $count);
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::SprintfUser';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: sprintf' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new(name => 'test', count => 42);
        my $got = $obj->format_string();
        die "format_string mismatch: $got" unless $got eq 'Name: test, Count: 42';
    }, 'format_string', todo => 'XS emitter: sprintf argument passing');
};

# ============================================================
# 4. split + regex
# ============================================================

subtest 'split with regex' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class SplitUser {
    field $text :param :reader;

    method word_count() {
        my @words = split /\s+/, $text;
        return scalar @words;
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::SplitUser';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: split with regex' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new(text => 'hello world foo');
        die "word_count != 3" unless $obj->word_count() == 3;
    }, 'word_count', todo => 'XS emitter: split with regex');
};

# ============================================================
# 5. next/last in loop
# ============================================================

subtest 'next unless in loop' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class NextUser {
    field $items :param :reader;

    method count_positive() {
        my $count = 0;
        for my $item ($items->@*) {
            next unless $item > 0;
            $count = $count + 1;
        }
        return $count;
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::NextUser';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: next unless in for-loop' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new(items => [-1, 2, -3, 4, 5]);
        die "count_positive != 3" unless $obj->count_positive() == 3;
    }, 'count_positive', todo => 'XS emitter: next unless in for-loop');
};

# ============================================================
# 6. Coderef invocation
# ============================================================

subtest 'coderef invocation' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class CoderefUser {
    field $callback :param :reader;

    method apply($value) {
        return $callback->($value);
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::CoderefUser';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: coderef invocation $f->($arg)' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new(callback => sub ($x) { $x * 2 });
        die "apply(21) != 42" unless $obj->apply(21) == 42;
    }, 'coderef apply', todo => 'XS emitter: coderef invocation $f->($arg)');
};

# ============================================================
# 7. isa operator
# ============================================================

subtest 'isa operator' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class IsaChecker {
    method check($obj) {
        if ($obj isa IsaChecker) {
            return "yes";
        }
        return "no";
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::IsaChecker';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: isa operator' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new();
        die "check(self) != yes" unless $obj->check($obj) eq 'yes';
        die "check(str) != no" unless $obj->check("not_an_object") eq 'no';
    }, 'isa check', todo => 'XS emitter: isa operator');
};

# ============================================================
# 8. String concat in loop (.= operator)
# ============================================================

subtest 'string concat in loop' => sub {
    my $source = <<'PERL';
use 5.42.0;
use utf8;
use experimental 'class';

class ConcatUser {
    field $parts :param :reader;

    method join_parts() {
        my $result = "";
        for my $part ($parts->@*) {
            $result .= $part;
        }
        return $result;
    }
}
PERL

    my $ir = parse_source_ir($source);
    ok(defined $ir, 'parse produces IR') or return;

    my $module = 'Chalk::XS::Construct::ConcatUser';
    my ($dist, $err) = build_and_load($ir, $module);
    TODO: {
        local $TODO = 'XS emitter: .= concat in for-loop' unless defined $dist;
        ok(defined $dist, 'XS builds') or do {
            diag $err if $err;
            return;
        };
    }
    return unless defined $dist;

    fork_test($module, sub ($mod) {
        my $obj = $mod->new(parts => ['hello', ' ', 'world']);
        die "join_parts mismatch" unless $obj->join_parts() eq 'hello world';
    }, 'join_parts');
};

done_testing();
