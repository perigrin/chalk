sub c { wantarray ? "L" : "S" } my @x = map { c() } 1; my @y = grep { c() eq "S" } 1; my $n = () = c(); print "@x@y$n\n";
