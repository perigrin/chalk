sub f { $_[0] > 0 ? ("p", $_[0]) : ("n") } my @a = f(3); my @b = f(-1); my $s = f(3); print scalar(@a), scalar(@b), "$s\n";
