my @r; my $i=0; while ($i<2) { my $v=$i++; push @r,\$v } print ${$r[0]}, ${$r[1]}, "\n";
