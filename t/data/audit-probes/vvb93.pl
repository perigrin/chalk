our @keep; sub k { push @keep, \$_[0] } my $i = 0; while ($i < 3) { my $x = $i++; k($x) } print join(",", map { $$_ } @keep), "\n";
