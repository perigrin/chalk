use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; our $g=1; if ($g) { zlow::poke(0) } print $g ? "t" : "f", "\n";
