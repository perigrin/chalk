my $s="x"; my $i=0; for (1..3) { if ($i++ % 2) { $s.="o" } else { $s=uc($s)."e" } } print "$s\n";
