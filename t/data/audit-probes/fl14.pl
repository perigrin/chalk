my $n = "abc"; { use warnings FATAL => "all"; my $r = eval { $n + 1 }; print defined $r ? "num" : "died", "\n"; }
