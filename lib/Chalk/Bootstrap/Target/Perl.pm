# ABOUTME: Perl code emitter that walks IR nodes and produces feature class source.
# ABOUTME: Generates Chalk::Grammar::BNF::Generated equivalent to hand-written BNF.pm.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::Target::Perl :isa(Chalk::Bootstrap::Target) {

    method generate($ir) {
        my $body = $self->_emit_body($ir);

        return $self->_preamble() . $body . $self->_postamble();
    }

    method _preamble() {
        return <<'PREAMBLE';
# ABOUTME: Generated BNF meta-grammar from bootstrap compiler.
# ABOUTME: Equivalent to hand-written Chalk::Grammar::BNF.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Grammar::BNF::Generated {
    use Chalk::Grammar::Rule;
    use Chalk::Grammar::Symbol;

    sub grammar {
        my @rules;

PREAMBLE
    }

    method _emit_body($ir) {
        return '';
    }

    method _postamble() {
        return <<'POSTAMBLE';
        return \@rules;
    }
}
POSTAMBLE
    }
}
