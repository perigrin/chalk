sub set { $_[0] = "s" } my $r = eval { set(1); 1 }; print $r ? "ok" : "died", "\n";
