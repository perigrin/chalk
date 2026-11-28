my $d = [1,2]; my $e = $d; $d = [@$d, 3]; print scalar(@$e), scalar(@$d), "\n";
