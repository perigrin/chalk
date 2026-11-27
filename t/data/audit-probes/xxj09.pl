my $s = "aXbXc"; my $n = 0; while ($s =~ /X/g) { $n += pos($s) } print "$n\n";
