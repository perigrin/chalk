use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use ZUp; ZUp::bump() for 1..2; my $v=$ZUp::n+1; print "$v\n";
