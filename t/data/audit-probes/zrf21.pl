my @r; my $v; for my $i (0..1) { $v=$i; push @r,\$v } print ${$r[0]}, ${$r[1]}, "\n";
