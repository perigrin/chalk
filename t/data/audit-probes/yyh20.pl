sub c { wantarray ? "L" : "S" } local $_ = c(); my $t = $_; my @l = (c()) x 2; my $n = c() x 2; print "$t@l$n\n";
