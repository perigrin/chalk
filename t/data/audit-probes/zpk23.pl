use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use ZUp; our $g=1; my $s=""; for (1..2) { $s.=$g; ZUp::poke($_+5); } print "$s$g\n";
