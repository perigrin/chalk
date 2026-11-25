use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; our $g=1; my $x=$g; zlow::call(sub { $g=5 }); print "$x$g\n";
