sub set { $_[0] = "s" } my $r = eval { set("lit"); 1 }; my $q = eval { set(1+1); 1 }; print $r ? "ok" : "died", $q ? "ok" : "died", "\n";
