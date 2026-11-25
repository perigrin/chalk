sub c { wantarray ? "L" : "S" } my @l = (0 || c()); my $s = (0 || c()); my @m = (1 && c()); my @t = (1 ? c() : 0); print "@l$s@m@t\n";
