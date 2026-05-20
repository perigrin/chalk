# ABOUTME: Tests Perl IR to Perl source code emission for Tier C files.
# ABOUTME: Validates generated Perl compiles, evals, and behaves equivalently.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate eval_module);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_perl_grammar('Chalk::Grammar::Perl::TargetPerlTierCTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# 5. Context.pm — extract, extend, duplicate, leaves, scanned_text
# ============================================================

{
    my $code = parse_and_generate($gen_grammar, 'lib/Chalk/Bootstrap/Context.pm');
    ok(defined $code, 'Context.pm: generated Perl code');

    SKIP: {
        skip 'Context.pm: no code generated', 10 unless defined $code;

        like($code, qr/method extract/, 'Context.pm: has method extract');
        like($code, qr/method extend/, 'Context.pm: has method extend');
        like($code, qr/method duplicate/, 'Context.pm: has method duplicate');
        like($code, qr/method leaves/, 'Context.pm: has method leaves');
        like($code, qr/method scanned_text/, 'Context.pm: has method scanned_text');

        # Rename and eval
        {
            my ($ok, $err) = eval_module($code,
                'Chalk::Bootstrap::Context',
                'Chalk::Bootstrap::ContextGenerated');
            ok($ok, 'Context.pm: evals cleanly') or diag "Error: $err";
        }

        SKIP: {
            my $eval_ok = eval { Chalk::Bootstrap::ContextGenerated->can('new') };
            skip 'Context.pm: eval not yet supported', 3 unless $eval_ok;

            my $ctx = Chalk::Bootstrap::ContextGenerated->new(focus => 'hello');
            is($ctx->extract(), 'hello', 'Context.pm: extract returns focus');

            my $ext = $ctx->extend(sub ($c) { return $c->extract() . ' world' });
            is($ext->extract(), 'hello world', 'Context.pm: extend applies function');

            my $scan_ctx = Chalk::Bootstrap::ContextGenerated->new(focus => 'foo');
            is($scan_ctx->scanned_text(), 'foo', 'Context.pm: scanned_text returns string focus');
        }
    }
}

done_testing();
