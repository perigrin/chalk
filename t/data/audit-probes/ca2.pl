sub f { return wantarray ? "list" : defined(wantarray) ? "scalar" : "void" } my @l = f(); my $s = f(); print "$l[0] $s\n";
