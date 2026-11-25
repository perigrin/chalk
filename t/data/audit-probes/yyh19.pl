sub c { wantarray ? "L" : "S" } my $s = sprintf("%s%s", c(), c()); my $t = "x" . (c())[0]; my ($u, $v) = (c(), scalar c()); print "$s$t$u$v\n";
