sub c { wantarray ? "L" : defined(wantarray) ? "S" : "V" } my @l = c(); my $s = c(); print "@l$s", c(), scalar(c()), "\n";
