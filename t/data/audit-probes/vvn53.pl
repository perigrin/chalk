my %r; for my $i (1..3) { $r{$i} = \$i } ${$r{2}} = 9; print join(",", map { ${$r{$_}} } sort keys %r), "\n";
