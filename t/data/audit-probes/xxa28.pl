sub f { $_[1] = "x" } my @a=(1); f(@a); print scalar(@a), "\n";
