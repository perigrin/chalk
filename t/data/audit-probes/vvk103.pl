my $n = 0; sub t { $n++; 1 } my $v = 0 ? t() : 1 ? 7 : t(); print "$v$n\n";
