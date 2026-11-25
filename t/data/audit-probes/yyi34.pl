my $r = eval { for my $x (1,2) { $x++ } 1 }; my $q = eval { $_++ for (1,2); 1 }; my $p = eval { for (1..2) { $_++ } 1 }; print $r ? "ok" : "died", $q ? "ok" : "died", $p ? "ok" : "died", "\n";
