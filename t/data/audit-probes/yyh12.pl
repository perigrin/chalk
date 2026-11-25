sub c { wantarray ? "L" : "S" } my @l = scalar(c()); my $j = join(",", c()); my @s = sort(c()); print "@l$j@s\n";
