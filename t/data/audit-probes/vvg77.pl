my $n = 1; my $c = sub { $n = 7; 0 }; if ($n == 1) { $c->(); print $n } print "\n";
