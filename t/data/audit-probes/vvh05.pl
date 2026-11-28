my $x = 1; my $r = eval { $x = 2; 7 }; print "$x$r", $@ eq "" ? "ok" : "err", "\n";
