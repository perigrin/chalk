my $s = "a b c"; my $n = () = $s =~ /\w/g; my @w = split ' ', $s; print "$n", scalar(@w), "\n";
