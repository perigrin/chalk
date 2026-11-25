my @r; for my $i (0..1) { my $v=$i; push @r,\$v } ${$r[0]}=5; print ${$r[0]}, ${$r[1]}, "\n";
