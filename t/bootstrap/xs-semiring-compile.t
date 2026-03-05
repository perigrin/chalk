# ABOUTME: Tests that all five semirings and FilterComposite compile to XS.
# ABOUTME: Verifies parsing, code generation, and multi-class assembly for the full semiring stack.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSSemiringCompile') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# --- Test: Parse and compile each semiring individually ---
my %parsed;
my @class_order = qw(Boolean Structural Precedence TypeInference SemanticAction FilterComposite);

for my $name (@class_order) {
    my $file = "lib/Chalk/Bootstrap/Semiring/${name}.pm";
    my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $file) };
    ok(defined $ir, "$name parses to IR") or do {
        diag "Parse failed: $@";
        next;
    };
    $parsed{$name} = { ir => $ir, sa => $sa, ctx => $ctx };

    # Try single-class XS generation
    my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => "Test::${name}",
    );
    my $code = eval { $xs->generate_with_cfg($ir, $sa, $ctx) };
    ok(defined $code, "$name compiles to XS")
        or diag "XS gen failed: $@";

    if (defined $code) {
        # Count dispatch methods
        my @cm = ($code =~ /call_method/g);
        my @impl = ($code =~ /_impl_/g);
        diag sprintf("  %s: call_method=%d  _impl_=%d  lines=%d",
            $name, scalar @cm, scalar @impl, scalar(split /\n/, $code));
    }
}

# --- Test: Multi-class assembly of all semirings ---
SKIP: {
    skip 'Not all semirings parsed', 3
        unless keys %parsed == scalar @class_order;

    my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
    for my $name (@class_order) {
        my $p = $parsed{$name};
        my @uses;
        if ($name eq 'FilterComposite') {
            @uses = qw(Boolean Structural Precedence TypeInference SemanticAction);
        }
        my $class_name = "Chalk::Bootstrap::Semiring::${name}";
        $reg->register($class_name, {
            ir => $p->{ir}, sa => $p->{sa}, ctx => $p->{ctx},
            uses => [map { "Chalk::Bootstrap::Semiring::$_" } @uses],
        });
    }

    my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => 'Test::FullSemiring',
        class_registry => $reg,
    );

    my @entries = map {
        my $p = $parsed{$_};
        {
            class_name => "Chalk::Bootstrap::Semiring::$_",
            ir => $p->{ir}, sa => $p->{sa}, ctx => $p->{ctx},
        }
    } @class_order;

    my $multi_code = eval { $xs->generate_multi_class(\@entries) };
    ok(defined $multi_code, 'multi-class semiring assembly succeeds')
        or diag "Multi-class gen failed: $@";

    SKIP: {
        skip 'Multi-class generation failed', 2 unless defined $multi_code;

        # Should have MODULE sections for each class
        my @module_sections = ($multi_code =~ /^MODULE\s*=/mg);
        is(scalar @module_sections, scalar @class_order,
            'one MODULE section per semiring class');

        # Should have exactly one BOOT block
        my @boot_blocks = ($multi_code =~ /^BOOT:/mg);
        is(scalar @boot_blocks, 1,
            'exactly one BOOT block in multi-class output');

        if (defined $multi_code) {
            my @cm = ($multi_code =~ /call_method/g);
            my @impl = ($multi_code =~ /_impl_/g);
            diag sprintf("  Multi-class: call_method=%d  _impl_=%d  lines=%d",
                scalar @cm, scalar @impl, scalar(split /\n/, $multi_code));
        }
    }
}

done_testing();
