sub set { $_[0] = "s" } my $r = eval { for my $x (1,2) { set($x) } 1 }; print $r ? "ok" : "died", "\n";
