use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; my $v = eval { YInit::bump(); die "x\n"; 1 } // $YInit::n; print "$v\n";
