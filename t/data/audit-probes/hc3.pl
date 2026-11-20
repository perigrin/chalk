my $r = [1, 2, 3]; my %h = (a => 1, b => 2); my @a = (1, 2, 3); my $n = () = ($r, $r); my $m = () = %h; my $k = () = (%h, @a, 5); print "$n $m $k $r->[2]\n";
