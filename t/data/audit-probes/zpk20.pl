use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; our $g=1; my $t = $g ? do { zlow::poke(5); $g } : 0; print "$t\n";
