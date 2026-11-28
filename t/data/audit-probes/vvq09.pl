my $v = 1; my $r = \$v; sub c { $v = 9; 0 } my $s = join(",", $$r, c()); print "$s\n";
