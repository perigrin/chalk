srand(42); my $r = rand(); my $i = int(rand(10)); print $r >= 0 && $r < 1 ? "ok" : "bad", $i >= 0 && $i < 10 ? "ok" : "bad", "\n";
